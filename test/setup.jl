using Augur
using Distributions

sim = Simulation()
defaults = joinpath(Pkg.dir("Augur"), "test", "defaults_noise.jl")
include(defaults)

function setup(sim::Simulation; reset::Bool=false)

    if reset
        sim = Simulation()
    end
    reload(defaults)

    sim.VERBOSE = false
    sim.TESTING = true
    sim.TEST_REPORTERS = ["true", "liar", "true", "liar", "liar", "liar"]
    sim.TEST_INIT_REP = ones(length(sim.TEST_REPORTERS))
    sim.TEST_CORRECT_ANSWERS = [ 2.0; 2.0; 1.0; 1.0 ]
    sim.TEST_REPORTS = [ 2.0 2.0 1.0 1.0 ;
                         2.0 1.0 1.0 1.0 ;
                         2.0 2.0 1.0 1.0 ;
                         2.0 2.0 2.0 1.0 ;
                         1.0 1.0 2.0 2.0 ;
                         1.0 1.0 2.0 2.0 ]
    sim.ITERMAX = 1
    sim.TIMESTEPS = 1
    sim.LIAR_THRESHOLD = 0.7
    sim.EVENTS = 4
    sim.REPORTERS = 6
    sim.SCALARS = 0.0
    sim.REP_RAND = false
    sim.BRIDGE = false
    sim.ALPHA = 0.1
    sim.CONSPIRACY = false
    sim.LABELSORT = false
    sim.HIERARCHICAL_THRESHOLD = 0.5
    sim.HIERARCHICAL_LINKAGE = :single
    sim.CLUSTERFECK_THRESHOLD = 0.5
    sim.DBSCAN_EPSILON = 0.5
    sim.DBSCAN_MINPOINTS = 1
    sim.ALGOS = [ "DBSCAN", "hierarchical", "PCA" ]

    trues = find(sim.TEST_REPORTERS .== "true")
    distorts = find(sim.TEST_REPORTERS .== "distort")
    liars = find(sim.TEST_REPORTERS .== "liar")
    num_trues = length(trues)
    num_distorts = length(distorts)
    num_liars = length(liars)
    reporters = (Symbol => Any)[
        :reporters => sim.TEST_REPORTERS,
        :trues => trues,
        :distorts => distorts,
        :liars => liars,
        :num_trues => num_trues,
        :num_distorts => num_distorts,
        :num_liars => num_liars,
        :honesty => nothing,
    ]
    (Symbol => Any)[
        :sim => sim,
        :reporters => reporters[:reporters],
        :honesty => reporters[:honesty],
        :correct_answers => sim.TEST_CORRECT_ANSWERS,
        :distorts => reporters[:distorts],
        :reports => sim.TEST_REPORTS,
        :num_distorts => reporters[:num_distorts],
        :num_trues => reporters[:num_trues],
        :num_liars => reporters[:num_liars],
        :trues => reporters[:trues],
        :liars => reporters[:liars],
    ]
end
