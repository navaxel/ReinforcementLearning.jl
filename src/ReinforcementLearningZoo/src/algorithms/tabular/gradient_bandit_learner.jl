export GradientBanditLearner

using Flux: softmax, onehot

Base.@kwdef struct GradientBanditLearner{A,B} <: Any
    approximator::A
    baseline::B
end

RLCore.forward!(learner::GradientBanditLearner, s::Int) = s |> learner.approximator |> softmax
RLCore.forward!(learner::GradientBanditLearner, env::AbstractEnv) = RLCore.forward!(learner, state(env))

function Base.push!(L::GradientBanditLearner, t::Any, ::AbstractEnv, ::PreActStage) end

function Base.push!(L::GradientBanditLearner, t::Any, ::AbstractEnv, ::PostActStage)
    A = L.approximator
    s, a, r = t[:state][end], t[:action][end], t[:reward][end]
    probs = s |> A |> softmax
    r̄ = L.baseline isa Number ? L.baseline : L.baseline(r)
    errors = (r - r̄) .* (onehot(a, 1:length(probs)) .- probs)
    update!(A, s => -errors)
end

function RLCore.update!(
    t::Any,
    ::QBasedPolicy{<:GradientBanditLearner},
    ::AbstractEnv,
    ::PreEpisodeStage,
)
    empty!(t)
end
