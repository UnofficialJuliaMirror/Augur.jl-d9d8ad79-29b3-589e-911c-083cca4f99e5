tic()

@everywhere using Simulator
using Distributions

liar_thresholds = 0.3:0.2:0.9
param_range = 5:5:250

sim = Simulation()

simtype = "liar"
if ~isinteractive() && length(ARGS) > 0
    if ARGS[1] == "cplx"
        simtype = "cplx"
    elseif ARGS[1] == "liar"
        simtype = "liar"
    else
        println("Unknown mode")
        exit()
    end
end

include("defaults_" * simtype * ".jl")

sim.VERBOSE = false

# Quick run-thru
# sim.EVENTS = 25
# sim.REPORTERS = 50
# sim.ITERMAX = 25
# sim.TIMESTEPS = 75

# Full(er) run
sim.EVENTS = 500
sim.REPORTERS = 1000
sim.ITERMAX = 200
sim.TIMESTEPS = 500

sim.SCALARS = 0.0
sim.REP_RAND = true
sim.REP_DIST = Pareto(3.0)

# "Preferential attachment" market size distribution
sim.MARKET_DIST = Pareto(3.0)

sim.ALPHA = 0.1
sim.BRIDGE = false
sim.CORRUPTION = 0.75
sim.RARE = 1e-5
sim.MONEYBIN = first(find(pdf(sim.MARKET_DIST, 1:1e4) .< sim.RARE))

sim.MAX_COMPONENTS = 5
sim.CONSPIRACY = false

sim.LABELSORT = true
sim.SAVE_RAW_DATA = false
sim.ALGOS = [
    "PCA",
    "fixed-variance",
    "big-five",
    "k-means",
    "hierarchy",
]

# Run simulations and save results:
#   - binary classifier quality metrics
#   - graphical algorithm comparison
if simtype == "liar"
    @time sim_data = run_simulations(liar_thresholds, sim; parallel=true)
    # plot_reptrack(sim_data)
    plot_simulations(sim_data)

# Timing/complexity
elseif simtype == "cplx"
    println("Timed simulations:")
    @time complexity(param_range, sim; iterations=1000, param="reporters")
    @time complexity(param_range, sim; iterations=1000, param="events")
    @time complexity(param_range, sim; iterations=1000, param="both")
end

t = toq()
if t <= 60
    units = "seconds"
elseif 60 < t <= 3600
    t /= 60
    units = "minutes"
elseif 3600 < t <= 86400
    t /= 3600
    units = "hours"
else
    t /= 86400
    units = "days"
end
print_with_color(:white, string(round(t, 4), " ", units, " elapsed\n"))
