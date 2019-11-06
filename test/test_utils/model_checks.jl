const GAEVF = JuMP.GenericAffExpr{Float64, VariableRef}
const GQEVF = JuMP.GenericQuadExpr{Float64, VariableRef}

function moi_tests(op_problem::OperationsProblem,
                   params::Bool,
                   vars::Int64,
                   interval::Int64,
                   lessthan::Int64,
                   greaterthan::Int64,
                   equalto::Int64,
                   binary::Bool)

    JuMPmodel = op_problem.canonical.JuMPmodel
    @test (:params in keys(JuMPmodel.ext)) == params
    @test JuMP.num_variables(JuMPmodel) == vars
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.Interval{Float64}) == interval
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.LessThan{Float64}) == lessthan
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.GreaterThan{Float64}) == greaterthan
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.EqualTo{Float64}) == equalto
    @test ((JuMP.VariableRef, MOI.ZeroOne) in JuMP.list_of_constraint_types(JuMPmodel)) == binary

    return

end

function psi_constraint_test(op_problem::OperationsProblem, constraint_names::Vector{Symbol})

    for con in constraint_names
        @test !isnothing(get(op_problem.canonical.constraints, con, nothing))
    end

    return

end

function psi_checkbinvar_test(op_problem::OperationsProblem, bin_variable_names::Vector{Symbol})

    for variable in bin_variable_names
        for v in op_problem.canonical.variables[variable]
            @test JuMP.is_binary(v)
        end
    end

    return

end

function psi_checkobjfun_test(op_problem::OperationsProblem, exp_type)

    @test JuMP.objective_function_type(op_problem.canonical.JuMPmodel) == exp_type

    return

end

function moi_lbvalue_test(op_problem::OperationsProblem, con_name::Symbol, value::Number)

    for con in op_problem.canonical.constraints[con_name]
        @test JuMP.constraint_object(con).set.lower == value
    end

    return

end

function psi_checksolve_test(op_problem::OperationsProblem, status)
    JuMP.optimize!(op_problem.canonical.JuMPmodel)
    @test termination_status(op_problem.canonical.JuMPmodel) in status
end

function psi_checksolve_test(op_problem::OperationsProblem, status, expected_result, tol = 0.0)
    res = solve_op_problem!(op_problem)
    @test termination_status(op_problem.canonical.JuMPmodel) in status
    @test isapprox(res.total_cost[:OBJECTIVE_FUNCTION], expected_result, atol = tol)
end
