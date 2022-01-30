module Interaction

# using Parameters, GreenFunc
# include(srcdir*"/parameter.jl")
# using .Parameter
# include(srcdir*"/convention.jl")
# using .Convention
# include(srcdir*"/polarization.jl")
# using .Polarization

using ..Parameter, ..Convention, ..Polarization
using ..Parameters, ..CompositeGrids, ..GreenFunc

export RPA, KO, RPAwrapped, KOwrapped, coulomb

# if !@isdefined Para
#     include(rundir*"/para.jl")
#     using .Para
# end

# println(Parameter.Param)
# @unpack me, kF, rs, e0, β , Λs, ϵ0= Parameter.Param

function inf_sum(q, n)
    # Calculate a series sum for Takada anzats
    # See Takada(doi:10.1103/PhysRevB.47.5202)(Eq.2.16).
    a = q * q
    sum = 1.0
    i = 0
    j = 1.0
    k = 2.0
    for i in 1:n
        sum = sum + a / j / k
        a = a * q * q
        j = j * (i + 1.0)
        k = k * (i + 2.0)
    end
    return 1.0 / sum / sum
end

"""
    function coulomb(q,param)

Bare interaction in momentum space. Coulomb interaction if Λs=0, Yukawa otherwise.

#Arguments:
 - q: momentum
 - param: other system parameters
"""
function coulomb(q, param)
    @unpack me, kF, rs, e0s, e0a, β, Λs, Λa, ϵ0 = param
    if (q^2 + Λs) * (q^2 + Λa) ≈ 0.0
        return 0.0, 0.0
    else
        return e0s^2 / ϵ0 / (q^2 + Λs), e0a^2 / ϵ0 / (q^2 + Λa)
    end
end

function bubbledyson(V::Float64, F::Float64, Π::Float64, n::Int)
    # V:bare interaction
    # F:F^{+-} is local field factor,0 for RPA
    # Π:Polarization. 2*Polarization0 for spin 1/2
    # n:matfreq. special case for n=0
    # comparing to previous convention, an additional V is multiplied
    K = 0
    if V ≈ 0
        K = Π * ( - F)^2 / (1.0 - (Π) * ( - F))
        return K
    end
    if n == 0
        if F == 0
            K = (V) * Π * (1)^2 / (1.0 / V - Π * (1))
        else
            K = (V) * Π * (1 - F / V)^2 / (1.0 / V - Π * (1 - F / V))
        end
    else
        K = Π * (V - F)^2 / (1.0 - (Π) * (V - F))
    end
    @assert !isnan(K) "nan at V=$V, F=$F, Π=$Π, n=$n"
    return K
end

function bubbledysonreg(V::Float64, F::Float64, Π::Float64, n::Int; regV::Float64 = V)
    # V:bare interaction
    # F:F^{+-} is local field factor,0 for RPA
    # Π:Polarization. 2*Polarization0 for spin 1/2
    # n:matfreq. special case for n=0
    # comparing to previous convention, an additional V is multiplied
    K = 0
    if V ≈ 0
        K = Π * ( - F)^2 / (1.0 - (Π) * ( - F)) / regV
        return K
    end
    if n == 0
        if F == 0
            K = Π * (1)^2 / (1.0 / V - Π * (1))
        else
            K = Π * (1 - F / V)^2 / (1.0 / V - Π * (1 - F / V))
        end
    else
        K = Π * (V - F)^2 / (1.0 - (Π) * (V - F)) / regV
    end
    @assert !isnan(K) "nan at V=$V, F=$F, Π=$Π, n=$n"
    return K
end

function bubblecorrection(q::Float64, n::Int, param;
    pifunc = Polarization0_ZeroTemp, landaufunc = landauParameterTakada, V_Bare = coulomb, isregularized = false)
    Fs::Float64, Fa::Float64 = landaufunc(q, n, param)
    Ks::Float64, Ka::Float64 = 0.0, 0.0
    Vs::Float64, Va::Float64 = V_Bare(q, param)
    @unpack spin = param

    if abs(q) > EPS
        Π::Float64 = spin * pifunc(q, n, param)
        if isregularized
            Ks = bubbledysonreg(Vs, Fs, Π, n, regV = Vs)
            Ka = bubbledysonreg(Va, Fa, Π, n, regV = Vs)
        else
            Ks = bubbledyson(Vs, Fs, Π, n)
            Ka = bubbledyson(Va, Fa, Π, n)
        end
    else
        Ks, Ka = 0.0, 0.0
    end

    return Ks, Ka
end

"""
    function RPA(q, n, param)

Dynamic part of RPA interaction, with polarization approximated by zero temperature Π0.

#Arguments:
 - q: momentum
 - n: matsubara frequency given in integer s.t. ωn=2πTn
 - param: other system parameters
"""
function RPA(q, n, param; pifunc = Polarization0_ZeroTemp, V_Bare = coulomb, isregularized = false)
    return bubblecorrection(q, n, param; pifunc = pifunc, landaufunc = landauParameter0, V_Bare = V_Bare, isregularized = isregularized)
end

function RPAwrapped(Euv, rtol, sgrid::SGT, param;
    pifunc = Polarization0_ZeroTemp, landaufunc = landauParameterTakada, V_Bare = coulomb) where {SGT}

    @unpack β = param
    gs = GreenFunc.Green2DLR{Float64}(:rpa, GreenFunc.IMFREQ, β, false, Euv, sgrid, 1; timeSymmetry = :ph, rtol = rtol)
    ga = GreenFunc.Green2DLR{Float64}(:rpa, GreenFunc.IMFREQ, β, false, Euv, sgrid, 1; timeSymmetry = :ph, rtol = rtol)
    green_dyn_s = zeros(Float64, (gs.color, gs.color, gs.spaceGrid.size, gs.timeGrid.size))
    green_ins_s = zeros(Float64, (gs.color, gs.color, gs.spaceGrid.size))
    green_dyn_a = zeros(Float64, (ga.color, ga.color, ga.spaceGrid.size, ga.timeGrid.size))
    green_ins_a = zeros(Float64, (ga.color, ga.color, ga.spaceGrid.size))
    for (ki, k) in enumerate(sgrid)
        for (ni, n) in enumerate(gs.dlrGrid.n)
            green_dyn_s[1, 1, ki, ni], green_dyn_a[1, 1, ki, ni] = RPA(k, n, param; pifunc = pifunc, V_Bare = V_Bare)
        end
        green_ins_s[1, 1, ki], green_ins_a[1, 1, ki] = V_Bare(k, param)
    end
    gs.dynamic = green_dyn_s
    gs.instant = green_ins_s
    ga.dynamic = green_dyn_a
    ga.instant = green_ins_a
    return gs, ga
end

"""
TODO    function landauParameterTakada(q, n, param)->exchange correlation kernel/Landau parameter

G factor with Takada's anzats. See Takada(doi:10.1103/PhysRevB.47.5202)(Eq.2.13-2.16).
Now Landau parameter F. F(+-)=G(+-)*V

#Arguments:
 - q: momentum
 - n: matsubara frequency given in integer s.t. ωn=2πTn
 - param: other system parameters
"""
function landauParameterTakada(q, n, param)
    @unpack me, kF, rs, e0s, e0, e0a, β, Λs, Λa, ϵ0 = param
    if e0 ≈ 0.0
        return 0.0, 0.0
    end
    r_s_dl = sqrt(4 * 0.521 * rs / π)
    C1 = 1 - r_s_dl * r_s_dl / 4.0 * (1 + 0.07671 * r_s_dl * r_s_dl * ((1 + 12.05 * r_s_dl) * (1 + 12.05 * r_s_dl) + 4.0 * 4.254 / 3.0 * r_s_dl * r_s_dl * (1 + 7.0 / 8.0 * 12.05 * r_s_dl) + 1.5 * 1.363 * r_s_dl * r_s_dl * r_s_dl * (1 + 8.0 / 9.0 * 12.05 * r_s_dl)) / (1 + 12.05 * r_s_dl + 4.254 * r_s_dl * r_s_dl + 1.363 * r_s_dl * r_s_dl * r_s_dl) / (1 + 12.05 * r_s_dl + 4.254 * r_s_dl * r_s_dl + 1.363 * r_s_dl * r_s_dl * r_s_dl))
    C2 = 1 - r_s_dl * r_s_dl / 4.0 * (1 + r_s_dl * r_s_dl / 8.0 * (log(r_s_dl * r_s_dl / (r_s_dl * r_s_dl + 0.990)) - (1.122 + 1.222 * r_s_dl * r_s_dl) / (1 + 0.533 * r_s_dl * r_s_dl + 0.184 * r_s_dl * r_s_dl * r_s_dl * r_s_dl)))
    D = inf_sum(r_s_dl, 100)
    A1 = (2.0 - C1 - C2) / 4.0 / e0^2 * π
    A2 = (C2 - C1) / 4.0 / e0^2 * π
    B1 = 6 * A1 / (D + 1.0)
    B2 = 2 * A2 / (1.0 - D)
    F_s = A1 * e0^2 / ϵ0 / (1.0 + B1 * q^2) + A2 * e0^2 / ϵ0 / (1.0 + B2 * q^2)
    F_a = A1 * e0^2 / ϵ0 / (1.0 + B1 * q^2) - A2 * e0^2 / ϵ0 / (1.0 + B2 * q^2)
    return F_s, F_a
end

@inline function landauParameter0(q, n, param)
    return 0.0, 0.0
end

"""
    function KO(q, n, param)

Dynamic part of KO interaction, with polarization approximated by zero temperature Π0.
Returns the spin symmetric part and asymmetric part separately.

#Arguments:
 - q: momentum
 - n: matsubara frequency given in integer s.t. ωn=2πTn
 - param: other system parameters
"""
function KO(q, n, param; pifunc = Polarization0_ZeroTemp, landaufunc = landauParameterTakada, V_Bare = coulomb, isregularized = false)
    return bubblecorrection(q, n, param; pifunc = pifunc, landaufunc = landaufunc, V_Bare = coulomb, isregularized = isregularized)
end

function KOwrapped(Euv, rtol, sgrid::SGT, param;
    pifunc = Polarization0_ZeroTemp, landaufunc = landauParameterTakada, V_Bare = coulomb) where {SGT}

    @unpack β = param
    gs = GreenFunc.Green2DLR{Float64}(:ko, GreenFunc.IMFREQ, β, false, Euv, sgrid, 1; timeSymmetry = :ph, rtol = rtol)
    ga = GreenFunc.Green2DLR{Float64}(:ko, GreenFunc.IMFREQ, β, false, Euv, sgrid, 1; timeSymmetry = :ph, rtol = rtol)
    green_dyn_s = zeros(Float64, (gs.color, gs.color, gs.spaceGrid.size, gs.timeGrid.size))
    green_ins_s = zeros(Float64, (gs.color, gs.color, gs.spaceGrid.size))
    green_dyn_a = zeros(Float64, (ga.color, ga.color, ga.spaceGrid.size, ga.timeGrid.size))
    green_ins_a = zeros(Float64, (ga.color, ga.color, ga.spaceGrid.size))
    for (ki, k) in enumerate(sgrid)
        for (ni, n) in enumerate(gs.dlrGrid.n)
            green_dyn_s[1, 1, ki, ni], green_dyn_a[1, 1, ki, ni] = KO(k, n, param; pifunc = pifunc, landaufunc = landaufunc, V_Bare = V_Bare)
        end
        green_ins_s[1, 1, ki], green_ins_a[1, 1, ki] = V_Bare(k, param)
    end
    gs.dynamic = green_dyn_s
    gs.instant = green_ins_s
    ga.dynamic = green_dyn_a
    ga.instant = green_ins_a
    return gs, ga
end

end
