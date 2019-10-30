abstract type AbstractRenewableFormulation <: AbstractDeviceFormulation end

abstract type AbstractRenewableDispatchFormulation <: AbstractRenewableFormulation end

struct RenewableFixed <: AbstractRenewableFormulation end

struct RenewableFullDispatch <: AbstractRenewableDispatchFormulation end

struct RenewableConstantPowerFactor <: AbstractRenewableDispatchFormulation end

########################### renewable generation variables #################################

function activepower_variables!(canonical::CanonicalModel,
                               devices::IS.FlattenIteratorWrapper{R}) where R<:PSY.RenewableGen

    add_variable(canonical,
                 devices,
                 Symbol("P_$(R)"),
                 false,
                 :nodal_balance_active;
                 lb_value = x -> 0.0,
                 ub_value = x -> PSY.get_rating(PSY.get_tech(x)))

    return

end

function reactivepower_variables!(canonical::CanonicalModel,
                                 devices::IS.FlattenIteratorWrapper{R}) where R<:PSY.RenewableGen

    add_variable(canonical,
                 devices,
                 Symbol("Q_$(R)"),
                 false,
                 :nodal_balance_reactive)

    return

end

####################################### Reactive Power Constraints #########################
function reactivepower_constraints!(canonical::CanonicalModel,
                                    devices::IS.FlattenIteratorWrapper{R},
                                    device_formulation::Type{RenewableFullDispatch},
                                    system_formulation::Type{<:PM.AbstractPowerModel}) where R<:PSY.RenewableGen

    range_data = Vector{NamedMinMax}(undef, length(devices))

    for (ix, d) in enumerate(devices)
        tech = PSY.get_tech(d)
        name = PSY.get_name(d)
        if isnothing(PSY.get_reactivepowerlimits(tech))
            limits = (min = 0.0, max = 0.0)
            range_data[ix] = (PSY.get_name(d), limits)
            @warn("Reactive Power Limits of $(name) are nothing. Q_$(name) is set to 0.0")
        else
            range_data[ix] = (name, PSY.get_reactivepowerlimits(tech))
        end
    end

    device_range(canonical,
                range_data,
                Symbol("reactiverange_$(R)"),
                Symbol("Q_$(R)"))

    return

end

function reactivepower_constraints!(canonical::CanonicalModel,
                                    devices::IS.FlattenIteratorWrapper{R},
                                    device_formulation::Type{RenewableConstantPowerFactor},
                                    system_formulation::Type{<:PM.AbstractPowerModel}) where R<:PSY.RenewableGen

    names = (PSY.get_name(d) for d in devices)
    time_steps = model_time_steps(canonical)
    p_variable_name = Symbol("P_$(R)")
    q_variable_name = Symbol("Q_$(R)")
    constraint_name = Symbol("reactiverange_$(R)")
    canonical.constraints[constraint_name] = JuMPConstraintArray(undef, names, time_steps)

    for t in time_steps, d in devices
        name = PSY.get_name(d)
        pf = sin(acos(PSY.get_powerfactor(PSY.get_tech(d))))
        canonical.constraints[constraint_name][name, t] = JuMP.@constraint(canonical.JuMPmodel,
                                canonical.variables[q_variable_name][name, t] ==
                                canonical.variables[p_variable_name][name, t] * pf)
    end

    return

end


######################## output constraints without Time Series ############################
function _get_time_series(canonical::CanonicalModel,
                          devices::IS.FlattenIteratorWrapper{<:PSY.RenewableGen})

    initial_time = model_initial_time(canonical)
    use_forecast_data = model_uses_forecasts(canonical)
    parameters = model_has_parameters(canonical)
    time_steps = model_time_steps(canonical)
    device_total = length(devices)
    ts_data_active = Vector{Tuple{String, Int64, Float64, Vector{Float64}}}(undef, device_total)
    ts_data_reactive = Vector{Tuple{String, Int64, Float64, Vector{Float64}}}(undef, device_total)

    for (ix, device) in enumerate(devices)
        bus_number = PSY.get_number(PSY.get_bus(device))
        name = PSY.get_name(device)
        tech = PSY.get_tech(device)
        pf = sin(acos(PSY.get_powerfactor(PSY.get_tech(device))))
        active_power = use_forecast_data ? PSY.get_rating(tech) : PSY.get_activepower(device)
        if use_forecast_data
            ts_vector = TS.values(PSY.get_data(PSY.get_forecast(PSY.Deterministic,
                                                                device,
                                                                initial_time,
                                                                "rating")))
        else
            ts_vector = ones(time_steps[end])
        end
        ts_data_active[ix] = (name, bus_number, active_power, ts_vector)
        ts_data_reactive[ix] = (name, bus_number, active_power * pf, ts_vector)
    end

    return ts_data_active, ts_data_reactive

end


function activepower_constraints!(canonical::CanonicalModel,
                                devices::IS.FlattenIteratorWrapper{R},
                                device_formulation::Type{<:AbstractRenewableDispatchFormulation},
                                system_formulation::Type{<:PM.AbstractPowerModel}) where R<:PSY.RenewableGen

    parameters = model_has_parameters(canonical)
    use_forecast_data = model_uses_forecasts(canonical)

    if !parameters && !use_forecast_data
        range_data = [(PSY.get_name(d), (min = 0.0, max = PSY.get_rating(PSY.get_tech(d)))) for d in devices]
        device_range(canonical,
                    range_data,
                    Symbol("activerange_$(R)"),
                    Symbol("P_$(R)"))
        return
    end

    ts_data_active, _ = _get_time_series(canonical, devices)
    if parameters
        device_timeseries_param_ub(canonical,
                            ts_data_active,
                            Symbol("activerange_$(R)"),
                            UpdateRef{R}(:rating),
                            Symbol("P_$(R)"))
    else
        device_timeseries_ub(canonical,
                            ts_data_active,
                            Symbol("activerange_$(R)"),
                            Symbol("P_$(R)"))
    end

    return

end

########################## Addition of to the nodal balances ###############################
function nodal_expression!(canonical::CanonicalModel,
                           devices::IS.FlattenIteratorWrapper{R},
                           system_formulation::Type{<:PM.AbstractPowerModel}) where R<:PSY.RenewableGen

    parameters = model_has_parameters(canonical)
    ts_data_active, ts_data_reactive = _get_time_series(canonical, devices)

    if parameters
        include_parameters(canonical,
                           ts_data_active,
                           UpdateRef{R}(:rating),
                           :nodal_balance_active)
        include_parameters(canonical,
                           ts_data_reactive,
                           UpdateRef{R}(:rating),
                           :nodal_balance_reactive)
        return
    end

    for t in model_time_steps(canonical)
        for device_value in ts_data_active
            _add_to_expression!(canonical.expressions[:nodal_balance_active],
                            device_value[2],
                            t,
                            device_value[3]*device_value[4][t])
        end
        for device_value in ts_data_reactive
            _add_to_expression!(canonical.expressions[:nodal_balance_reactive],
                            device_value[2],
                            t,
                            device_value[3]*device_value[4][t])
        end
    end

    return

end

function nodal_expression!(canonical::CanonicalModel,
                           devices::IS.FlattenIteratorWrapper{R},
                           system_formulation::Type{<:PM.AbstractActivePowerModel}) where R<:PSY.RenewableGen

    parameters = model_has_parameters(canonical)
    ts_data_active, ts_data_reactive = _get_time_series(canonical, devices)

    if parameters
        include_parameters(canonical,
                           ts_data_active,
                           UpdateRef{R}(:rating),
                           :nodal_balance_active)
        return
    end

    for t in model_time_steps(canonical)
        for device_value in ts_data_active
            _add_to_expression!(canonical.expressions[:nodal_balance_active],
                            device_value[2],
                            t,
                            device_value[3]*device_value[4][t])
        end
    end

    return

end

##################################### renewable generation cost ############################
function cost_function(canonical::CanonicalModel,
                       devices::IS.FlattenIteratorWrapper{PSY.RenewableDispatch},
                       device_formulation::Type{D},
                       system_formulation::Type{<:PM.AbstractPowerModel}) where D<:AbstractRenewableDispatchFormulation

    add_to_cost(canonical,
                devices,
                Symbol("P_RenewableDispatch"),
                :fixed,
                -1.0)

    return

end
