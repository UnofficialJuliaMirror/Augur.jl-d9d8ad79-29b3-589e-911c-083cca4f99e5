@pyimport pyconsensus

function simulate(sim::Simulation)
    iterate = (Int64)[]
    i = 1
    reporters = []
    raw_data = (String => Any)[ "sim" => sim ]
    timesteps = (sim.SAVE_RAW_DATA) ? 1:sim.TIMESTEPS : sim.TIMESTEPS
    for algo in sim.ALGOS
        raw_data[algo] = Dict{String,Any}()
        for m in [sim.METRICS, "components"]
            raw_data[algo][m] = Dict{Int,Vector{Float64}}()
            for t in timesteps
                raw_data[algo][m][t] = Float64[]
            end
        end
        # raw_data[algo]["repcount"] = Dict{Int,Vector{Dict{Float64,Int}}}()
        # for t in timesteps
        #     raw_data[algo]["repcount"][t] = Dict{Float64,Int}[]
        # end
    end
    track = Dict{String,Dict{Symbol,Matrix{Float64}}}()
    A = Dict{String,Any}()
    for algo in sim.ALGOS
        A[algo] = Dict{String,Any}()
        track[algo] = Dict{Symbol,Matrix{Float64}}()
        for tr in sim.TRACK
            track[algo][tr] = zeros(sim.TIMESTEPS, sim.ITERMAX)
        end
    end

    # Reputation time series (repbox):
    # - column t is the reputation vector at time t
    # - third axis = iteration
    if sim.VERBOSE
        repbox = Dict{String,Array{Float64,3}}()
        repdelta = Dict{String,Array{Float64,3}}()
        for algo in sim.ALGOS
            repbox[algo] = zeros(sim.REPORTERS, sim.TIMESTEPS, sim.ITERMAX)
            repdelta[algo] = zeros(sim.REPORTERS, sim.TIMESTEPS, sim.ITERMAX)
        end
    end

    while i <= sim.ITERMAX
        for algo in sim.ALGOS

            # Create reporters and assign each reporter a label
            reporters = create_reporters(sim)

            # Simulate over #TIMESTEPS consensus resolutions:
            #   - The previous (smoothed) reputation is used as an input to
            #     the next time step
            #   - Reporters' labels (true, liar, etc.) do not change
            #   - Correct answers and reports are generated fresh at each
            #     time step
            metrics = Dict{Symbol,Float64}()
            for t = 1:sim.TIMESTEPS

                # Generate reports and correct answers
                data = generate_data(sim, reporters)

                # Assign/update reputation
                reputation = (t == 1) ?
                    init_reputation(sim) : A[algo]["agents"]["smooth_rep"]

                if sim.VERBOSE
                    repbox[algo][:,t,i] = reputation
                    repdelta[algo][:,t,i] = reputation - repbox[algo][:,1,i]
                    print_with_color(:white, "t = $t:\n")
                    display([data[:reporters] repdelta[algo][:,:,i]])
                    println("")

                    # print_with_color(:white, "Reputation [" * algo * "]:\n")
                    # display(reputation')
                    # println("")

                    # print_with_color(:white, "Reports [" * algo * "]:\n")
                    # display(data[:reports])
                    # println("")
                end

                if algo == "cokurtosis"

                    # Per-user cokurtosis contribution
                    data[:aux] = [
                        :cokurt => JointMoments.collapse(
                            data[:reports],
                            reputation;
                            order=4,
                            standardize=false,
                            axis=2,
                            normalized=true,
                            bias=0,
                        )
                    ]
                    if sim.VERBOSE
                        print_with_color(:white, "Collapsed [" * algo * "]:\n")
                        display(data[:aux])
                        println("")
                    end

                elseif algo == "covariance"

                    # Per-user covariance contribution
                    data[:aux] = [
                        :cov => JointMoments.collapse(
                            data[:reports],
                            reputation;
                            order=2,
                            axis=2,
                            normalized=true,
                            bias=0,
                        )
                    ]
                    if sim.VERBOSE
                        print_with_color(:white, "Collapsed [" * algo * "]:\n")
                        display(data[:aux])
                        println("")
                    end

                elseif algo == "virial"

                    data[:aux] = [:H => zeros(sim.REPORTERS)]
                    for o = 2:2:sim.VIRIALMAX
                        data[:aux][:H] += JointMoments.collapse(
                            data[:reports],
                            reputation;
                            order=o,
                            axis=2,
                            normalized=true,
                            bias=0,
                        ) / o
                    end
                    data[:aux][:H] = JointMoments.normalize(data[:aux][:H])
                    if sim.VERBOSE
                        print_with_color(:white, "Collapsed [" * algo * "]:\n")
                        display(data[:aux])
                        println("")
                    end

                end

                # Use pyconsensus for event resolution
                A[algo] = pyconsensus.Oracle(
                    reports=data[:reports],
                    reputation=reputation,
                    alpha=sim.ALPHA,
                    variance_threshold=sim.VARIANCE_THRESHOLD,
                    aux=data[:aux],
                    algorithm=algo,
                )[:consensus]()

                # Measure this algorithm's performance
                metrics = compute_metrics(
                    sim,
                    data,
                    A[algo]["events"]["outcomes_final"],
                    reputation,
                    A[algo]["agents"]["smooth_rep"],
                )

                if sim.VERBOSE
                    print_with_color(:white, "Oracle output [" * algo * "]:\n")
                    display(A[algo])
                    println("")
                    display(A[algo]["agents"])
                    println("")
                    display(A[algo]["events"])
                    println("")

                    print_with_color(:white, "Metrics [" * algo * "]:\n")
                    display(metrics)
                    println("")
                end

                if sim.SAVE_RAW_DATA || t == sim.TIMESTEPS
                    for m in sim.METRICS
                        push!(raw_data[algo][m][t], metrics[symbol(m)])
                    end
                    push!(raw_data[algo]["components"][t], A[algo]["components"])
                    # push!(raw_data[algo]["repcount"][t], metrics[:repcount])
                end

                # Track the system's evolution
                for tr in sim.TRACK
                    track[algo][tr][t,i] = metrics[tr]
                end
            end
        end

        push!(iterate, i)
        i += 1
    end
    if sim.SAVE_RAW_DATA
        filename = "data/raw/raw_sim_" * repr(now()) * ".jld"
        jldopen(filename, "w") do file
            write(file, "raw_data", raw_data)
            write(file, "track", track)
            if sim.VERBOSE
                write(file, "repbox", repbox)
                write(file, "repdelta", repdelta)
            end
        end
    end

    # Tracking stats: mean +/- standard error time series
    trajectory = Trajectory()
    for algo in sim.ALGOS
        trajectory[algo] = Track()
        for tr in sim.TRACK
            trajectory[algo][tr] = (Symbol => Vector{Float64})[
                :mean => mean(track[algo][tr], 2)[:],
                :stderr => std(track[algo][tr], 2)[:] / sim.SQRTN,
            ]
        end
    end

    # Sum down repbox tubes (for surface plots)
    if sim.VERBOSE
        reptrack = Dict{String,Dict{String,Matrix{Float64}}}()
        for algo in sim.ALGOS
            reptrack[algo] = Dict{String,Matrix{Float64}}()
            for s in ("mean", "median", "std")
                reptrack[algo][s] = squeeze(mean(repbox[algo], 3), 3)
            end
            if sim.VERBOSE
                print_with_color(:white, "Reputation evolution:\n")
                display(reptrack[algo]["mean"])
                println("")
            end
        end
    end

    # Convert raw data into means and standard errors for plotting
    processed_data = (String => Any)[
        "iterate" => iterate,
        "liar_threshold" => sim.LIAR_THRESHOLD,
        "trajectory" => trajectory,
        "reptrack" => reptrack,
    ]
    @inbounds for algo in sim.ALGOS
        processed_data[algo] = Dict{String,Dict{String,Float64}}()
        for s in sim.STATISTICS
            processed_data[algo][s] = Dict{String,Float64}()
            sfun = (s == "mean") ? mean : (v) -> std(v) / sim.SQRTN
            for m in [sim.METRICS, "components"]
                processed_data[algo][s][m] = sfun(raw_data[algo][m][sim.TIMESTEPS])
            end
        end
    end
    processed_data
end

function exclude(sim::Simulation, excluded::Tuple)
    for x in excluded
        sim.METRICS = sim.METRICS[sim.METRICS .!= string(x)]
        sim.TRACK = sim.TRACK[sim.TRACK .!= x]
    end
    sim
end

function preprocess(sim::Simulation)
    sim = (sim.DISTORTER) ?
        exclude(sim, (:MCC, :sensitivity, :fallout, :precision)) :
        exclude(sim, (:distorts_bonus, :distorts_rep))
    (sim.BRIDGE) ?
        exclude(sim, (:beats, :liars_bonus, :sensitivity, :fallout,
                      :precision, :MCC, :true_rep, :liar_rep, :gap)) :
        exclude(sim, (:corrupted,))
end

function run_simulations(ltr::Range, sim::Simulation; parallel::Bool=false)
    print_with_color(:red, "Simulating:\n")
    sim = preprocess(sim)
    ~sim.VERBOSE || xdump(sim)

    # Run parallel simulations
    if parallel && nprocs() > 1
        raw::Array{Dict{String,Any},1} = @sync @parallel (vcat) for lt in ltr
            println(lt)
            sim.LIAR_THRESHOLD = lt
            simulate(sim)
        end

    # Regular (serial) simulation
    else
        raw = Dict{String,Any}[]
        for (i, lt) in enumerate(ltr)
            print_with_color(:yellow, "Liar threshold: " * repr(lt) * "\n")
            sim.LIAR_THRESHOLD = lt
            raw = vcat(raw, simulate(sim))
        end
    end

    # Set up final results dictionary
    gridrows = length(ltr)
    results = Dict{String,Any}()
    @inbounds for algo in sim.ALGOS
        results[algo] = Dict{String,Dict}()
        for s in sim.STATISTICS
            results[algo][s] = Dict{String,Array}()
            for m in [sim.METRICS, "components"]
                results[algo][s][m] = zeros(gridrows)
            end
        end
    end

    # Sort results using liar_threshold values
    results["reptracks"] = Array(Dict{String,Dict{String,Matrix{Float64}}}, gridrows)
    results["trajectories"] = Array(Trajectory, gridrows)
    @inbounds for (row, liar_threshold) in enumerate(ltr)
        i = 1
        matched = Dict{String,Dict}()
        for i = 1:gridrows
            if raw[i]["liar_threshold"] == liar_threshold
                matched = splice!(raw, i)
                break
            end
        end
        results["iterate"] = matched["iterate"]
        results["trajectories"][row] = matched["trajectory"]
        results["reptracks"][row] = matched["reptrack"]
        for algo in sim.ALGOS
            for s in sim.STATISTICS
                for m in [sim.METRICS, "components"]
                    results[algo][s][m][row,1] = matched[algo][s][m]
                end
            end
        end
    end
    save_data(sim, results, ltr)
end

function run_simulations(ltr::Range;
                         algos::Vector{ASCIIString}=["cokurtosis"],
                         save_raw_data::Bool=false)
    sim = Simulation()
    sim.ALGOS = algos
    sim.SAVE_RAW_DATA = save_raw_data
    run_simulations(ltr, sim)
end
