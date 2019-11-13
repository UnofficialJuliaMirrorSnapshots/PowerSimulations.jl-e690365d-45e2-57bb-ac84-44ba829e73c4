abstract type AbstractLoadFormulation <: AbstractDeviceFormulation end

abstract type AbstractControllablePowerLoadFormulation <: AbstractLoadFormulation end

struct StaticPowerLoad <: AbstractLoadFormulation end

struct InterruptiblePowerLoad <: AbstractControllablePowerLoadFormulation end

struct DispatchablePowerLoad <: AbstractControllablePowerLoadFormulation end

########################### dispatchable load variables ####################################
function activepower_variables!(canonical::Canonical,
                               devices::IS.FlattenIteratorWrapper{L}) where L<:PSY.ElectricLoad
    add_variable(canonical,
                 devices,
                 Symbol("P_$(L)"),
                 false,
                 :nodal_balance_active, -1.0;
                 ub_value = x -> PSY.get_maxactivepower(x),
                 lb_value = x -> 0.0)

    return

end


function reactivepower_variables!(canonical::Canonical,
                                 devices::IS.FlattenIteratorWrapper{L}) where L<:PSY.ElectricLoad
    add_variable(canonical,
                 devices,
                 Symbol("Q_$(L)"),
                 false,
                 :nodal_balance_reactive, -1.0;
                 ub_value = x -> PSY.get_maxreactivepower(x),
                 lb_value = x -> 0.0)

    return

end

function commitment_variables!(canonical::Canonical,
                              devices::IS.FlattenIteratorWrapper{L}) where L<:PSY.ElectricLoad

    add_variable(canonical,
                 devices,
                 Symbol("ON_$(L)"),
                 true)

    return

end

####################################### Reactive Power Constraints #########################
"""
Reactive Power Constraints on Loads Assume Constant PowerFactor
"""
function reactivepower_constraints!(canonical::Canonical,
                                   devices::IS.FlattenIteratorWrapper{L},
                                   device_formulation::Type{<:AbstractControllablePowerLoadFormulation},
                                   system_formulation::Type{<:PM.AbstractPowerModel}) where L<:PSY.ElectricLoad

    time_steps = model_time_steps(canonical)
    key = Symbol("reactive_$(L)")
    canonical.constraints[key] = JuMPConstraintArray(undef, (PSY.get_name(d) for d in devices), time_steps)

    for t in time_steps, d in devices
        name = PSY.get_name(d)
        pf = sin(atan((PSY.get_maxreactivepower(d)/PSY.get_maxactivepower(d))))
        canonical.constraints[key][PSY.get_name(d), t] = JuMP.@constraint(canonical.JuMPmodel,
                        canonical.variables[Symbol("Q_$(L)")][name, t] == canonical.variables[Symbol("P_$(L)")][name, t]*pf)
    end

    return

end


######################## output constraints without Time Series ############################
function _get_time_series(canonical::Canonical,
                          devices::IS.FlattenIteratorWrapper{<:PSY.ElectricLoad})

    initial_time = model_initial_time(canonical)
    use_forecast_data = model_uses_forecasts(canonical)
    time_steps = model_time_steps(canonical)
    device_total = length(devices)
    ts_data_active = Vector{Tuple{String, Int64, Float64, Vector{Float64}}}(undef, device_total)
    ts_data_reactive = Vector{Tuple{String, Int64, Float64, Vector{Float64}}}(undef, device_total)

    for (ix, device) in enumerate(devices)
        bus_number = PSY.get_number(PSY.get_bus(device))
        name = PSY.get_name(device)
        active_power = use_forecast_data ? PSY.get_maxactivepower(device) : PSY.get_activepower(device)
        reactive_power = use_forecast_data ? PSY.get_maxreactivepower(device) : PSY.get_reactivepower(device)
        if use_forecast_data
            forecast = PSY.get_forecast(PSY.Deterministic,
                                        device,
                                        initial_time,
                                        "get_maxactivepower",
                                        length(time_steps))
            ts_vector = TS.values(PSY.get_data(forecast))
        else
            ts_vector = ones(time_steps[end])
        end
        ts_data_active[ix] = (name, bus_number, active_power, ts_vector)
        ts_data_reactive[ix] = (name, bus_number, reactive_power, ts_vector)
    end

    return ts_data_active, ts_data_reactive

end

function activepower_constraints!(canonical::Canonical,
                                 devices::IS.FlattenIteratorWrapper{L},
                                 device_formulation::Type{DispatchablePowerLoad},
                                 system_formulation::Type{<:PM.AbstractPowerModel}) where L<:PSY.ElectricLoad

    parameters = model_has_parameters(canonical)
    use_forecast_data = model_uses_forecasts(canonical)

    if !parameters && !use_forecast_data
        range_data = [(PSY.get_name(d), (min = 0.0, max = PSY.get_activepower(d))) for d in devices]
        device_range(canonical,
                    range_data,
                    Symbol("activerange_$(L)"),
                    Symbol("P_$(L)"))
        return
    end

    ts_data_active, _ = _get_time_series(canonical, devices)
    if parameters
        device_timeseries_param_ub(canonical,
                                   ts_data_active,
                                   Symbol("active_$(L)"),
                                   UpdateRef{L}("get_maxactivepower"),
                                   Symbol("P_$(L)"))
    else
        device_timeseries_ub(canonical,
                            ts_data_active,
                            Symbol("active_$(L)"),
                            Symbol("P_$(L)"))
    end

    return

end

function activepower_constraints!(canonical::Canonical,
                                 devices::IS.FlattenIteratorWrapper{L},
                                 device_formulation::Type{InterruptiblePowerLoad},
                                 system_formulation::Type{<:PM.AbstractPowerModel}) where L<:PSY.ElectricLoad

    parameters = model_has_parameters(canonical)
    use_forecast_data = model_uses_forecasts(canonical)

    if !parameters && !use_forecast_data
        range_data = [(PSY.get_name(d), (min = 0.0, max = PSY.get_activepower(d))) for d in devices]
        device_range(canonical,
                    range_data,
                    Symbol("activerange_$(L)"),
                    Symbol("P_$(L)"))
        return
    end

    ts_data_active, _ = _get_time_series(canonical, devices)
    if parameters
        device_timeseries_ub_bigM(canonical,
                                 ts_data_active,
                                 Symbol("active_$(L)"),
                                 Symbol("P_$(L)"),
                                 UpdateRef{L}("get_maxactivepower"),
                                 Symbol("ON_$(L)"))
    else
        device_timeseries_ub_bin(canonical,
                                ts_data_active,
                                Symbol("active_$(L)"),
                                Symbol("P_$(L)"),
                                Symbol("ON_$(L)"))
    end

    return

end


########################## Addition of to the nodal balances ###############################
function nodal_expression!(canonical::Canonical,
                           devices::IS.FlattenIteratorWrapper{L},
                           system_formulation::Type{<:PM.AbstractPowerModel}) where L<:PSY.ElectricLoad


    ts_data_active, ts_data_reactive = _get_time_series(canonical, devices)
    parameters = model_has_parameters(canonical)

    if parameters
        include_parameters(canonical,
                        ts_data_active,
                        UpdateRef{L}("get_maxactivepower"),
                        :nodal_balance_active,
                        -1.0)
        include_parameters(canonical,
                        ts_data_reactive,
                        UpdateRef{L}("get_maxactivepower"),
                        :nodal_balance_reactive,
                        -1.0)
        return
    end

    for t in model_time_steps(canonical)
        for device_value in ts_data_active
            _add_to_expression!(canonical.expressions[:nodal_balance_active],
                            device_value[2],
                            t,
                            -device_value[3]*device_value[4][t])
        end
        for device_value in ts_data_reactive
            _add_to_expression!(canonical.expressions[:nodal_balance_reactive],
                            device_value[2],
                            t,
                            -device_value[3]*device_value[4][t])
        end
    end

    return


end

function nodal_expression!(canonical::Canonical,
                           devices::IS.FlattenIteratorWrapper{L},
                           system_formulation::Type{<:PM.AbstractActivePowerModel}) where L<:PSY.ElectricLoad


    parameters = model_has_parameters(canonical)
    ts_data_active, _ = _get_time_series(canonical, devices)

    if parameters
        include_parameters(canonical,
                        ts_data_active,
                        UpdateRef{L}("get_maxactivepower"),
                        :nodal_balance_active,
                        -1.0)
        return
    end

    for t in model_time_steps(canonical), device_value in ts_data_active
        _add_to_expression!(canonical.expressions[:nodal_balance_active],
                            device_value[2],
                            t,
                            -device_value[3]*device_value[4][t])
    end

    return
end

############################## FormulationControllable Load Cost ###########################
function cost_function(canonical::Canonical,
                       devices::IS.FlattenIteratorWrapper{L},
                       device_formulation::Type{DispatchablePowerLoad},
                       system_formulation::Type{<:PM.AbstractPowerModel}) where L<:PSY.ControllableLoad

    add_to_cost(canonical,
                devices,
                Symbol("P_$(L)"),
                :variable,
                -1.0)

    return

end

function cost_function(canonical::Canonical,
                       devices::IS.FlattenIteratorWrapper{L},
                       device_formulation::Type{InterruptiblePowerLoad},
                       system_formulation::Type{<:PM.AbstractPowerModel}) where L<:PSY.ControllableLoad

    add_to_cost(canonical,
                devices,
                Symbol("ON_$(L)"),
                :fixed,
                -1.0)

    return

end
