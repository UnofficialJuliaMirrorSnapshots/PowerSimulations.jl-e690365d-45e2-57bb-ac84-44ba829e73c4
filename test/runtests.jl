using PowerSimulations
using PowerSystems
using PowerModels
using Dates
using JuMP
using Test
using Ipopt
using GLPK
using OSQP

const PM = PowerModels
const PSY = PowerSystems
const PSI = PowerSimulations

abstract type TestOptModel<:PSI.AbstractOperationModel end

ipopt_optimizer = JuMP.with_optimizer(Ipopt.Optimizer, print_level = 0)
ipopt_ws_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6, mu_init=1e-4, print_level=0)
GLPK_optimizer = JuMP.with_optimizer(GLPK.Optimizer)
OSQP_optimizer = JuMP.with_optimizer(OSQP.Optimizer, verbose = false)

include("test_utils/get_test_data.jl")
include("test_utils/model_checks.jl")

if !Sys.iswindows()

    @testset "Common Functionalities" begin
        include("test_base_structs.jl")
        include("test_PowerModels_interface.jl")
    end

    @testset "Device Constructors" begin
        include("test_thermal_generation_constructors.jl")
        include("test_renewable_generation_constructors.jl")
        include("test_load_constructors.jl")
        include("test_storage_constructors.jl")
        include("test_hydro_generation_constructors.jl")
    end

    @testset "Network Constructors" begin
        include("test_network_constructors.jl")
    end

    @testset "Services Constructors" begin
        #include("test_services_constructor.jl")
    end

end

@testset "Operation Models" begin
    include("test_operation_model_constructor.jl")
    include("test_operation_model_solve.jl")
end

@testset "Simulation Models" begin
    #include("test_simulation_models.jl")
end
