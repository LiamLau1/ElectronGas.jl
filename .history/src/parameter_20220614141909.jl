"""
Template of parameter. A submodule of ElectronGas.

    Use the convention where ħ=1, k_B=1.
    Only stores parameters that might change for purposes.
"""
module Parameter

# using Parameters
using ..Parameters
# using Roots, SpecialFunctions
# using Polylogarithms

@with_kw struct Para
    WID::Int = 1

    dim::Int = 3    # dimension (D=2 or 3, doesn't work for other D!!!)
    spin::Int = 2  # number of spins

    # prime parameters
    ϵ0::Float64 = 1 / (4π)
    e0::Float64 = sqrt(2) # electron charge
    me::Float64 = 0.5  # electron mass
    EF::Float64 = 1.0     #kF^2 / (2me)
    β::Float64 = 200 # bare inverse temperature
    μ::Float64 = 1.0

    # artificial parameters
    Λs::Float64 = 0.0   # Yukawa-type spin-symmetric interaction  ~1/(q^2+Λs)
    Λa::Float64 = 0.0   # Yukawa-type spin-antisymmetric interaction ~1/(q^2+Λa)
    gs::Float64 = 1.0   # spin-symmetric coupling 
    ga::Float64 = 0.0   # spin-antisymmetric coupling

    # derived parameters
    beta::Float64 = β * EF
    Θ::Float64 = 1.0 / β / EF
    T::Float64 = 1.0 / β
    n::Float64 = (dim == 3) ? (EF * 2 * me)^(3 / 2) / (6π^2) * spin : me * EF / π
    Rs::Float64 = (dim == 3) ? (3 / (4π * n))^(1 / 3) : sqrt(1 / (π * n))
    a0::Float64 = 4π * ϵ0 / (me * e0^2)
    rs::Float64 = Rs / a0
    kF::Float64 = sqrt(2 * me * EF)
    espin::Float64 = e0
    e0s::Float64 = e0
    e0a::Float64 = espin
    NF::Float64 = (dim == 3) ? spin * me * kF / 2 / π^2 : spin * me / 2 / π
end

derived_para_names = (:beta, :Θ, :T, :n, :Rs, :a0, :rs, :kF, :espin, :e0s, :e0a, :NF)

"""
    function derive(param::Para; kws...)

Reconstruct a new Para with given key word arguments.
This is needed because the default reconstruct generated by Parameters.jl
could not handle derived parameters correctly.

#Arguments:
 - param: only "non-derived" fields that's not mentioned in kws are extracted from param
 - kws...: new values
"""
derive(param::Para; kws...) = _reconstruct(param, kws)
derive(param::Para, di::Union{AbstractDict,Tuple{Symbol,Any}}) = _reconstruct(param, di)

# reconstruct(pp::Para, di) = reconstruct(Para, pp, di)
# reconstruct(pp; kws...) = reconstruct(pp, kws)
# reconstruct(Para::Type, pp; kws...) = reconstruct(Para, pp, kws)

function _reconstruct(pp::Para, di)
    # default reconstruct can't handle derived parameters correctly
    di = !isa(di, AbstractDict) ? Dict(di) : copy(di)
    ns = fieldnames(Para)
    args = []
    for (i, n) in enumerate(ns)
        if n ∉ derived_para_names
            # if exist in di, use value from di
            # the default value is from pp
            push!(args, (n, pop!(di, n, getfield(pp, n))))
        else
            pop!(di, n, getfield(pp, n))
        end
    end
    length(di) != 0 && error("Fields $(keys(di)) not in type $T")

    dargs = Dict(args)
    return Para(; dargs...)
end

# function Base.getproperty(obj::Para, sym::Symbol)
#     if sym === :beta # dimensionless beta
#         return obj.β * obj.EF
#     elseif sym === :Θ # dimensionless temperature
#         return 1.0 / obj.β / obj.EF
#     elseif sym === :T
#         return 1.0 / obj.β
#     elseif sym === :n
#         return (obj.dim == 3) ? (obj.EF * 2 * obj.me)^(3 / 2) / (6π^2) * obj.spin : obj.me * obj.EF / π
#     elseif sym === :Rs
#         return (obj.dim == 3) ? (3 / (4π * obj.n))^(1 / 3) : sqrt(1 / (π * obj.n))
#     elseif sym === :a0
#         return 4π * obj.ϵ0 / (obj.me * obj.e0^2)
#     elseif sym === :rs
#         return obj.Rs / obj.a0
#     elseif sym === :kF
#         return sqrt(2 * obj.me * obj.EF)
#     elseif sym === :e0s
#         return obj.e0
#     elseif sym === :e0a
#         return obj.espin
#     else # fallback to getfield
#         return getfield(obj, sym)
#     end
# end

# """
#     function chemical_potential(beta)

# generate chemical potential μ with given beta and density conservation.

# #Arguments:
#  - beta: dimensionless inverse temperature
# """
# function chemical_potential(beta, dim)
#     f(β, μ) = real(polylog(dim / 2, -exp(β * μ))) + 1 / gamma(1 + dim / 2) * (β)^(dim / 2)
#     g(μ) = f(beta, μ)
#     return find_zero(g, (-1e4, 1))
# end

"""
    function fullUnit(ϵ0, e0, me, EF, β)

generate Para with a complete set of parameters, no value presumed.

#Arguments:
 - ϵ0: vacuum permittivity
 - e0: electron charge
 - me: electron mass
 - EF: Fermi energy
 - β: inverse temperature
"""
@inline function fullUnit(ϵ0, e0, me, EF, β, dim=3, spin=2; kwargs...)
    # μ = try
    #     chemical_potential(β * EF, dim) * EF
    # catch e
    #     # if isa(e, StackOverflowError)
    #     EF
    # end
    μ = EF
    println(kwargs)

    para = Para(dim=dim,
        spin=spin,
        ϵ0=ϵ0,
        e0=e0,
        me=me,
        EF=EF,
        β=β,
        μ=μ,
        kwargs...
    )
    return para
    # return reconstruct(para, kwargs...)
end

"""
    function defaultUnit(Θ, rs)

assume 4πϵ0=1, me=0.5, EF=1

#Arguments:
 - Θ: dimensionless temperature. Since EF=1 we have β=beta
 - rs: Wigner-Seitz radius over Bohr radius.
"""
@inline function defaultUnit(Θ, rs, dim=3, spin=2; kwargs...)
    ϵ0 = 1 / (4π)
    e0 = (dim == 3) ? sqrt(2 * rs / (9π / (2spin))^(1 / 3)) : sqrt(sqrt(2) * rs)
    me = 0.5
    EF = 1
    β = 1 / Θ / EF
    return fullUnit(ϵ0, e0, me, EF, β, dim, spin; kwargs...)
end


"""
    function rydbergUnit(Θ, rs, dim = 3, spin = 2; kwargs...)

assume 4πϵ0=1, me=0.5, e0=sqrt(2)

#Arguments:
 - Θ: dimensionless temperature. beta could be different from β
 - rs: Wigner-Seitz radius over Bohr radius.
 - dim: dimension of the system
 - spin: spin = 1 or 2
 - kwargs: user may explicity set other paramters using the key/value pairs
"""
@inline function rydbergUnit(Θ, rs, dim=3, spin=2; kwargs...)
    ϵ0 = 1 / (4π)
    e0 = sqrt(2)
    me = 0.5
    kF = (dim == 3) ? (9π / (2spin))^(1 / 3) / rs : sqrt(4 / spin) / rs
    EF = kF^2 / (2me)
    β = 1 / Θ / EF
    return fullUnit(ϵ0, e0, me, EF, β, dim, spin; kwargs...)
end


"""
    function atomicUnit(Θ, rs, dim = 3, spin = 2; kwargs...)

assume 4πϵ0=1, me=1, e0=1

#Arguments:
 - Θ: dimensionless temperature. beta could be different from β
 - rs: Wigner-Seitz radius over Bohr radius.
 - dim: dimension of the system
 - spin: spin = 1 or 2
 - kwargs: user may explicity set other paramters using the key/value pairs
"""
@inline function atomicUnit(Θ, rs, dim=3, spin=2; kwargs...)
    ϵ0 = 1 / (4π)
    e0 = 1
    me = 1
    kF = (dim == 3) ? (9π / (2spin))^(1 / 3) / rs : sqrt(4 / spin) / rs
    EF = kF^2 / (2me)
    β = 1 / Θ / EF
    return fullUnit(ϵ0, e0, me, EF, β, dim, spin; kwargs...)
end





"""
    isZeroT(para) = (para.β == Inf)

    check if it is at zero temperature or not.
"""
isZeroT(para) = (para.β == Inf)

export Para, Param

end
