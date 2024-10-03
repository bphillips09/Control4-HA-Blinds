BLIND_PROXY = 5001
SUPPORTED_FEATURES = 0
SUPPORTS_STOP = false
SUPPORTS_LEVEL = false
SUPPORTS_OPEN = false
SUPPORTS_CLOSE = false
IS_TILT = false
CURRENT_LEVEL = 0
OPEN_LEVEL = 0
CLOSE_LEVEL = 1
FEATURES = {
    OPEN = 1,
    CLOSE = 2,
    SET_POSITION = 4,
    STOP = 8,
    OPEN_TILT = 16,
    CLOSE_TILT = 32,
    STOP_TILT = 64,
    SET_TILT_POSITION = 128
}

function RFP.SET_LEVEL_TARGET(idBinding, strCommand, tParams)
    if (IS_TILT) then
        CoverControl("set_cover_tilt_position", tParams.LEVEL_TARGET)
    else
        CoverControl("set_cover_position", tParams.LEVEL_TARGET)
    end
end

function RFP.UP(idBinding, strCommand)
    if (IS_TILT) then
        CoverControl("open_cover_tilt")
    else
        CoverControl("open_cover")
    end
end

function RFP.DOWN(idBinding, strCommand)
    if (IS_TILT) then
        CoverControl("close_cover_tilt")
    else
        CoverControl("close_cover")
    end
end

function RFP.STOP(idBinding, strCommand)
    if (IS_TILT) then
        CoverControl("stop_cover_tilt")
    else
        CoverControl("stop_cover")
    end
end

function RFP.BUTTON_ACTION(idBinding, strCommand, tParams)
    if tParams.ACTION == "2" then
        if tParams.BUTTON_ID == "0" then
            RFP:SET_LEVEL_TARGET(strCommand, { LEVEL_TARGET = 0 })
        elseif tParams.BUTTON_ID == "1" then
            RFP:SET_LEVEL_TARGET(strCommand, { LEVEL_TARGET = 100 })
        else
            if (CURRENT_LEVEL == 100) then
                RFP:SET_LEVEL_TARGET(strCommand, { LEVEL_TARGET = 0 })
            else
                RFP:SET_LEVEL_TARGET(strCommand, { LEVEL_TARGET = 100 })
            end
        end
    end
end

function RFP.DO_CLICK(idBinding, strCommand, tParams)
    local tParams = {
        ACTION = "2",
        BUTTON_ID = ""
    }

    if idBinding == 200 then
        tParams.BUTTON_ID = "0"
    elseif idBinding == 201 then
        tParams.BUTTON_ID = "1"
    elseif idBinding == 202 then
        tParams.BUTTON_ID = "2"
    end

    RFP:BUTTON_ACTION(strCommand, tParams)
end

function CoverControl(service, position)
    local switchServiceCall = {
        domain = "cover",
        service = service,

        service_data = {
            position = position
        },

        target = {
            entity_id = EntityID
        }
    }

    local tParams = {
        JSON = JSON:encode(switchServiceCall)
    }

    C4:SendToProxy(999, "HA_CALL_SERVICE", tParams)
end

function IsFeatureSupported(supported_features, feature)
    return BitwiseAnd(supported_features, feature) ~= 0
end

function RFP.RECEIEVE_STATE(idBinding, strCommand, tParams)
    local jsonData = JSON:decode(tParams.response)

    local stateData

    if jsonData ~= nil then
        stateData = jsonData
    end

    Parse(stateData)
end

function RFP.RECEIEVE_EVENT(idBinding, strCommand, tParams)
    local jsonData = JSON:decode(tParams.data)

    local eventData

    if jsonData ~= nil then
        eventData = jsonData["event"]["data"]["new_state"]
    end

    Parse(eventData)
end

function Parse(data)
    if data == nil then
        print("NO DATA")
        return
    end

    if data["entity_id"] ~= EntityID then
        return
    end

    local state = data["state"]
    local attributes = data["attributes"]

    if not Connected then
        Connected = true
    end

    if attributes == nil then
        return
    end

    local selectedAttribute = attributes["supported_features"]
    if SUPPORTED_FEATURES ~= selectedAttribute then
        SUPPORTED_FEATURES = selectedAttribute

        SUPPORTS_OPEN = IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.OPEN) or
            IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.OPEN_TILT)

        SUPPORTS_CLOSE = IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.CLOSE) or
            IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.CLOSE_TILT)

        SUPPORTS_STOP = IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.STOP) or
            IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.STOP_TILT)

        SUPPORTS_LEVEL = IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.SET_POSITION) or
            IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.SET_TILT_POSITION)

        IS_TILT = IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.OPEN_TILT) or
            IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.CLOSE_TILT) or
            IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.STOP_TILT) or
            IsFeatureSupported(SUPPORTED_FEATURES, FEATURES.SET_TILT_POSITION)

        if (SUPPORTS_LEVEL) then
            OPEN_LEVEL = 100
            CLOSE_LEVEL = 0
        elseif (SUPPORTS_STOP) then
            OPEN_LEVEL = 2
            CLOSE_LEVEL = 0
        else
            OPEN_LEVEL = 1
            CLOSE_LEVEL = 0
        end

        C4:SendToProxy(BLIND_PROXY, "SET_CAN_STOP", { CAN_STOP = SUPPORTS_STOP }, "NOTIFY", true)
        C4:SendToProxy(BLIND_PROXY, "SET_HAS_LEVEL", {
            HAS_LEVEL = SUPPORTS_LEVEL,
            LEVEL_OPEN = OPEN_LEVEL,
            LEVEL_CLOSED = CLOSE_LEVEL,
            LEVEL_SECONDARY_CLOSED = "",
            LEVEL_UNKNOWN = -1,
            LEVEL_DISCRETE_CONTROL = SUPPORTS_LEVEL,
            HAS_LEVEL_SECONDARY_CLOSED = false
        }, "NOTIFY", true)
    end

    C4:UpdateProperty('Supports Open/Close', tostring(SUPPORTS_OPEN or SUPPORTS_CLOSE))
    C4:UpdateProperty('Supports Stop', tostring(SUPPORTS_STOP))
    C4:UpdateProperty('Supports Level', tostring(SUPPORTS_LEVEL))
    C4:UpdateProperty('Supports Tilt', tostring(IS_TILT))

    selectedAttribute = attributes["current_position"]
    if (selectedAttribute == nil or IS_TILT) then
        selectedAttribute = attributes["current_tilt_position"]
    end

    if (selectedAttribute == nil) then
        if state ~= nil then
            if state == "open" then
                RELAY_STATE = state
                C4:SendToProxy(BLIND_PROXY, 'STOPPED', { LEVEL = OPEN_LEVEL }, "NOTIFY", true)
            elseif state == "closed" then
                RELAY_STATE = state
                C4:SendToProxy(BLIND_PROXY, 'STOPPED', { LEVEL = CLOSE_LEVEL }, "NOTIFY", true)
            end
        end
        return
    end

    CURRENT_LEVEL = (math.floor((tonumber(selectedAttribute))+0.5))

    C4:UpdateProperty('Current Level', tostring(CURRENT_LEVEL))

    if state ~= nil then
        if state == "open" then
            RELAY_STATE = state
            C4:SendToProxy(BLIND_PROXY, 'STOPPED', { LEVEL = CURRENT_LEVEL }, "NOTIFY", true)
        elseif state == "closed" then
            RELAY_STATE = state
            C4:SendToProxy(BLIND_PROXY, 'STOPPED', { LEVEL = CURRENT_LEVEL }, "NOTIFY", true)
        end
    end
end
