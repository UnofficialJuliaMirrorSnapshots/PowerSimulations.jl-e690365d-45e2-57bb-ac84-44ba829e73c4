construct_device!(canonical::Canonical, sys::PSY.System,
                  model::DeviceModel{B, Br},
                  ::Type{CopperPlatePowerModel};
                  kwargs...) where {B<:PSY.DCBranch,
                                    Br<:AbstractBranchFormulation} = nothing

construct_device!(canonical::Canonical, sys::PSY.System,
                  model::DeviceModel{B, Br},
                  ::Type{CopperPlatePowerModel};
                  kwargs...) where {B<:PSY.ACBranch,
                                    Br<:AbstractBranchFormulation} = nothing

function construct_device!(canonical::Canonical, sys::PSY.System,
                           model::DeviceModel{B, Br},
                           ::Type{S};
                           kwargs...) where {B<:PSY.Branch,
                                             Br<:AbstractBranchFormulation,
                                             S<:PM.AbstractPowerModel}



    devices = PSY.get_components(B, sys)

    if validate_available_devices(devices,B)
        return
    end

    branch_rate_bounds!(canonical, devices, Br, S)

    branch_rate_constraint!(canonical, devices, Br, S)

    return

end

function construct_device!(canonical::Canonical, sys::PSY.System,
                           model::DeviceModel{PSY.MonitoredLine, FlowMonitoredLine},
                           ::Type{S};
                           kwargs...) where {S<:PM.AbstractPowerModel}



    devices = PSY.get_components(PSY.MonitoredLine, sys)

    if validate_available_devices(devices, PSY.MonitoredLine)
        return
    end

    branch_rate_bounds!(canonical,
                        devices,
                        model.formulation,
                        S)

    branch_rate_constraint!(canonical,
                        devices,
                        model.formulation,
                        S)

    branch_flow_constraint!(canonical,
                        devices,
                        model.formulation,
                        S)

    return

end

 construct_device!(canonical::Canonical, sys::PSY.System,
                   model::DeviceModel{B, Br},
                   ::Type{S};
                   kwargs...) where {B<:PSY.Branch,
                                     Br<:Union{Type{StaticLineUnbounded},
                                               Type{StaticTransformerUnbounded}},
                                     S<:PM.AbstractPowerModel} = nothing

function construct_device!(canonical::Canonical, sys::PSY.System,
                           model::DeviceModel{B, Br},
                           ::Type{S};
                           kwargs...) where {Br<:AbstractBranchFormulation,
                                             B<:PSY.DCBranch,
                                             S<:PM.AbstractPowerModel}



    devices = PSY.get_components(B, sys)

    if validate_available_devices(devices, B)
        return
    end

    branch_rate_constraint!(canonical, devices, Br, S)

    return

end
