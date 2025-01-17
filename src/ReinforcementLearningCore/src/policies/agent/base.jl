export Agent

using Base.Threads: @spawn

using Functors: @functor
import Base.push!
"""
    Agent(;policy, trajectory) <: AbstractPolicy

A wrapper of an `AbstractPolicy`. Generally speaking, it does nothing but to
update the trajectory and policy appropriately in different stages. Agent
is a Callable and its call method accepts varargs and keyword arguments to be
passed to the policy. 

"""
mutable struct Agent{P,T,C} <: AbstractPolicy
    policy::P
    trajectory::T
    cache::C # need cache to collect elements as trajectory does not support partial inserting

    function Agent(policy::P, trajectory::T) where {P,T}
        agent = new{P,T, SRT}(policy, trajectory, SRT())

        if TrajectoryStyle(trajectory) === AsyncTrajectoryStyle()
            bind(trajectory, @spawn(optimise!(policy, trajectory)))
        end
        agent
    end

    function Agent(policy::P, trajectory::T, cache::C) where {P,T,C}
        agent = new{P,T,C}(policy, trajectory, cache)

        if TrajectoryStyle(trajectory) === AsyncTrajectoryStyle()
            bind(trajectory, @spawn(optimise!(policy, trajectory)))
        end
        agent
    end
end

Agent(;policy, trajectory, cache = SRT()) = Agent(policy, trajectory, cache)

RLBase.optimise!(agent::Agent, stage::S) where {S<:AbstractStage} =RLBase.optimise!(TrajectoryStyle(agent.trajectory), agent, stage)
RLBase.optimise!(::SyncTrajectoryStyle, agent::Agent, stage::S) where {S<:AbstractStage} =
    RLBase.optimise!(agent.policy, stage, agent.trajectory)

# already spawn a task to optimise inner policy when initializing the agent
RLBase.optimise!(::AsyncTrajectoryStyle, agent::Agent, stage::S) where {S<:AbstractStage} = nothing

#by default, optimise does nothing at all stage
function RLBase.optimise!(policy::AbstractPolicy, stage::AbstractStage, trajectory::Trajectory) end

@functor Agent (policy,)

function Base.push!(agent::Agent, ::PreActStage, env::AbstractEnv)
    push!(agent, state(env))
end

# !!! TODO: In async scenarios, parameters of the policy may still be updating
# (partially), which will result to incorrect action. This should be addressed
# in Oolong.jl with a wrapper
function RLBase.plan!(agent::Agent{P,T,C}, env::AbstractEnv) where {P,T,C}
    action = RLBase.plan!(agent.policy, env)
    push!(agent.trajectory, agent.cache, action)
    action
end

# Multiagent Version
function RLBase.plan!(agent::Agent{P,T,C}, env::E, p::Symbol) where {P,T,C,E<:AbstractEnv}
    action = RLBase.plan!(agent.policy, env, p)
    push!(agent.trajectory, agent.cache, action)
    action
end

function Base.push!(agent::Agent{P,T,C}, ::PostActStage, env::E) where {P,T,C,E<:AbstractEnv}
    push!(agent.cache, reward(env), is_terminated(env))
end

function Base.push!(agent::Agent, ::PostExperimentStage, env::E) where {E<:AbstractEnv}
    RLBase.reset!(agent.cache)
end

function Base.push!(agent::Agent, ::PostExperimentStage, env::E, player::Symbol) where {E<:AbstractEnv}
    RLBase.reset!(agent.cache)
end

function Base.push!(agent::Agent{P,T,C}, state::S) where {P,T,C,S}
    push!(agent.cache, state)
end

