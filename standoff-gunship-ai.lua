settings = {
    targetAltitude = 100,
    minAltitude = 100,
    maxAltitude = 400,
    maxPitch = 30,
    maxRoll = 20,
    targetDistance = 1500,
    
    enablePitchToTarget = false,
    
    enableAltitudeMatching = false,
    altitudeMatchingOffset = 50,
    
    enableTerrainAvoidance = true,
    terrainAvoidanceLookahead = 3,
    terrainAvoidanceSamples = 5,
    terrainRestrictSeaLevel = true,
    
    maxLiftPercentage = 1,
    maxSlidePercentage = 1,
    maxThrustPercentage = 1,
    
    enableDodging = true,
    dodgeFrequency = 2,
    dodgeMultiplier = {x = .5, y = 1, z = 4},
    
    enableTiltRotor = true,
    rotorTiltSpinblockSetup = {},
    maxRotorTilt = 45,
    
    ignoredRotors = {10, 11},
    
    hasLift = "auto",
    hasThrust = "auto",
    hasSlide = "auto"
}

maxTimeToTarget = 3
guidanceMinDistance = 50

pidFactors = {
        altitude = {.5, .01, .05},
        thrust = {.1, .05, .01},
        slide = {.1, .01, .05},
        roll = {.01, .001, .001},
        pitch = {.1, .01, .05},
        yaw = {.1, .01, .05},
        rotorTilt = {.1, .01, .01}
}

--  Built-in variables and constants. Do not modify without good reason.
integrals = {}
prevErrors = {}
tickRate = 1/40
tickCounter = 0

init = false
vehicle = {
    size = Vector3(25,10,25),
    thrusters = {},
    spinners = {},
    tilts = {},
    ignoredRotors = settings.ignoredRotors,
    tiltRotors = settings.rotorTiltSpinblockSetup,
    position = Vector3(0,0,0),
    heading = Vector3(0,0,0),
    velocity = Vector3(0,0,0),
    velocityMagnitude = 0,
    forwardsVelocity = 0,
    slideVelocity = 0,
    yaw = 0,
    pitch = 0,
    roll = 0,
    inverted = 1,
    mainframes = 0,
    hasThrust = false,
    hasSlide = false,
    hasLift = false,
    hasTarget = false,
    hadTarget = false,
    terrainPrediction = 0,
    lastHealth = 1,
    ticksSinceDodge = 0,
    docked = false
}

targets = {}
dodgeTargets = {x = 0, y = 0, z = 0}

output = {
    thrust = 0,
    altitude = 0,
    slide = 0,
    roll = 0,
    pitch = 0,
    yaw = 0
}

CONST = {
    WATER = 0,
    LAND = 1,
    AIR = 2,
    YAWLEFT = 0,
    YAWRIGHT = 1,
    ROLLLEFT = 2,
    ROLLRIGHT = 3,
    NOSEUP = 4,
    NOSEDOWN = 5,
    INCREASE = 6,
    DECREASE = 7,
    MAIN = 8,
    THRUSTER = 9,
    SPINNERSPEED = 30,
}

function Update(I)
    local health = I:GetHealthFraction()
    if (vehicle.lastHealth ~= health or init == false) then
        selfDetect(I)
        init = true
    end
    
    if (I:IsDocked()) then
        vehicle.docked = true
        integrals = {}
        prevErrors = {}
    else
        vehicle.docked = false
    end
        
    update(I)
    control(I)
    thrust(I)
end

--  Detect parameters about the vehicle
function selfDetect(I)
    I:Log("Detecting vehicle properties")
    
    vehicle.mainframes = I:GetNumberOfMainframes()
    vehicle.size = I:GetConstructMaxDimensions() - I:GetConstructMinDimensions()
    
    --  Detect thruster properties. If set to autodetect, check if translation directions are covered.
    local thrusterCount = I:Component_GetCount(CONST.THRUSTER)
    local ix = 0
    local iy = 0
    vehicle.thrusters = {}
   
    --  Prepare variables for determining available thrust/slide/lift thrust
    if (settings.hasThrust == "auto") then vehicle.hasThrust = false end
    if (settings.hasSlide == "auto") then vehicle.hasSlide = false end
    if (settings.hasLift == "auto") then vehicle.hasLift = false end
    
    local slideControls = {false,false,false,false}
    local thrustControls = {false,false}
    local liftControls = {false,false,false,false}
    
    --  Iterate through thrusters, detecting each thruster and its position/orientation
    for ix = 0, thrusterCount - 1 do
        vehicle.thrusters[ix] = I:Component_GetBlockInfo(CONST.THRUSTER, ix)
        
        --  Check if we have thrusters in front and back of the center of mass facing both directions, indicating full control over slide
        if (vehicle.hasSlide == false and math.abs(vehicle.thrusters[ix].LocalForwards.x) > .95) then
            if (vehicle.thrusters[ix].LocalPositionRelativeToCom.z > 0) then
                if (vehicle.thrusters[ix].LocalForwards.x > 0) then
                    slideControls[0] = true
                else
                    slideControls[1] = true
                end
            elseif (vehicle.thrusters[ix].LocalPositionRelativeToCom.z < 0) then
                if (vehicle.thrusters[ix].LocalForwards.x > 0) then
                    slideControls[3] = true
                else
                    slideControls[2] = true
                end
            else
                if (vehicle.thrusters[ix].LocalForwards.x > 0) then
                    slideControls[0] = true
                    slideControls[3] = true
                else
                    slideControls[1] = true
                    slideControls[2] = true
                end
            end
        end
        
        --  Check if we have thrusters in front and back of the center of mass facing upwards, indicating full control over lift
        if (vehicle.hasLift == false and math.abs(vehicle.thrusters[ix].LocalForwards.y) > .95) then
            if (vehicle.thrusters[ix].LocalPositionRelativeToCom.z > 0 and vehicle.thrusters[ix].LocalForwards.y > 0) then
                liftControls[0] = true
            elseif (vehicle.thrusters[ix].LocalPositionRelativeToCom.z < 0 and vehicle.thrusters[ix].LocalForwards.y > 0) then
                liftControls[1] = true
            elseif (vehicle.thrusters[ix].LocalForwards.y > 0) then
                liftControls[0] = true
                liftControls[1] = true
            end
        end
        
        --  Check if we have thrusters to the left and right of center of mass facing backwards and forwards, indicating full control over thrust
        if (vehicle.hasThrust == false and math.abs(vehicle.thrusters[ix].LocalForwards.z) > .95) then
            if (vehicle.thrusters[ix].LocalPositionRelativeToCom.x > 0) then
                if (vehicle.thrusters[ix].LocalForwards.z > 0) then
                    thrustControls[0] = true
                else
                    thrustControls[1] = true
                end
            elseif (vehicle.thrusters[ix].LocalPositionRelativeToCom.x < 0) then
                if (vehicle.thrusters[ix].LocalForwards.z > 0) then
                    thrustControls[3] = true
                else
                    thrustControls[2] = true
                end
            else
                if (vehicle.thrusters[ix].LocalForwards.z > 0) then
                    thrustControls[0] = true
                    thrustControls[3] = true
                else
                    thrustControls[1] = true
                    thrustControls[2] = true
                end
            end
        end
    end

    local normalSpinners = {}
    local spinnerCount = I:GetSpinnerCount()

    --  Iterate through spinners, identifying each spinner and its position/orientation. Ignore any spinners configured on tilt rotors.
    for ix = 0, spinnerCount - 1 do
        local ignoreThisRotor = false
        for iy,val in pairs(vehicle.ignoredRotors) do
            if (val == ix) then ignoreThisRotor = true end
        end
        
        --  Only detect information about enabled spinners.
        if (ignoreThisRotor == false) then
            local heliSpinner = I:IsSpinnerDedicatedHelispinner(ix)
            local onHull = I:IsSpinnerOnHull(ix)
            local spinnerInfo = I:GetSpinnerInfo(ix)

            if (heliSpinner and onHull) then
                vehicle.spinners[ix] = {info = spinnerInfo}
                vehicle.spinners[ix].upVector = getUpVectorFromRotation(vehicle.spinners[ix].info.LocalRotation)

                if (vehicle.hasSlide == false and math.abs(vehicle.spinners[ix].upVector.x) > .05) then
                    if (vehicle.spinners[ix].info.LocalPositionRelativeToCom.z > 0) then
                        slideControls[0] = true
                        slideControls[1] = true
                    elseif (vehicle.spinners[ix].info.LocalPositionRelativeToCom.z < 0) then
                        slideControls[2] = true
                        slideControls[3] = true
                    else
                        slideControls[0] = true
                        slideControls[1] = true
                        slideControls[2] = true
                        slideControls[3] = true
                    end
                end
                
                if (vehicle.hasLift == false and math.abs(vehicle.spinners[ix].upVector.y) > .05) then
                    liftControls[0] = true
                    liftControls[1] = true
                end
                
                if (vehicle.hasThrust == false and math.abs(vehicle.spinners[ix].upVector.z) > .05) then
                    if (vehicle.spinners[ix].info.LocalPositionRelativeToCom.x > 0) then
                        thrustControls[0] = true
                        thrustControls[1] = true
                    elseif (vehicle.spinners[ix].info.LocalPositionRelativeToCom.x < 0) then
                        thrustControls[2] = true
                        thrustControls[3] = true
                    else
                        thrustControls[0] = true
                        thrustControls[1] = true
                        thrustControls[2] = true
                        thrustControls[3] = true
                    end
                end
            elseif (heliSpinner == false) then
                normalSpinners[ix] = spinnerInfo
            end
        end
    end

    --  Check if we have any spinners to treat differently due to tilt-rotor configuration
    local spinnerCount = I:GetSpinnerCount()
    local val = {}
    local rotors = -1
    
    --  If tilt rotor config is enabled and the user pre-configured the tilt rotors, assume their configuration is correct
    if (settings.enableTiltRotor and table.getn(vehicle.tiltRotors) > 0) then
        for ix,val in pairs(vehicle.tiltRotors) do
            
            --  If this is a dedicated spinner, the configuration is incorrect. Else, set up details about the detected dedicated spinners
            if (I:IsSpinnerDedicatedHelispinner(ix) == false) then
                
                table.insert(vehicle.ignoredRotors, ix)
                local spinnerInfo = I:GetSpinnerInfo(ix)
                local spinnerDetails = {info = spinnerInfo, rotors = val, upVector = getUpVectorFromRotation(spinnerInfo.LocalRotation), startRotation = spinnerInfo.LocalRotation}
                
                vehicle.tilts[ix] = spinnerDetails
                I:Log("Detected tilt rotor")
            else
                I:Log("Warning: spinner "..ix.." as defined by tilt-rotor configuration is not attached to the hull, and cannot be used to tilt attached rotors.")
            end
            
            --  Automatically ignore the detected spinblock. It's a tilt-rotor; you really don't want to try and spin it like a propeller.
            for iy,rotor in pairs(val) do
                table.insert(vehicle.ignoredRotors, rotor)
            end
        end
    --  If tilt rotors are enabled and the user didn't pre-configure them, let's autodetect the spinblocks by seeing which ones aren't on the hull
    elseif (settings.enableTiltRotor) then
        for ix = 0, spinnerCount - 1 do
            local heliSpinner = I:IsSpinnerDedicatedHelispinner(ix)
            local onHull = I:IsSpinnerOnHull(ix)
            local spinnerInfo = I:GetSpinnerInfo(ix)

            --  If this is a dedicated spinblock on another spinblock, ignore it in further calculations and get its information
            if (heliSpinner and onHull == false) then
                local lowestDistIndex = -1
                local lowestDist = 99999

                --  Look at our list of regular spinblocks. If this is the closest one we've seen so far, save its index.
                for spinIndex, tiltSpinner in pairs(normalSpinners) do
                    local dist = (spinnerInfo.Position - tiltSpinner.Position).magnitude
                    if (dist < lowestDist) then
                        lowestDistIndex = spinIndex
                        lowestDist = dist
                    end
                end

                --  If we haven't seen one, something is wrong and the universe has probably imploded (or FtD just hasn't rendered some damage yet)
                if (lowestDistIndex == -1) then
                    I:LogToHud("Error: tilt-rotor autodetection failure. Cannot determine nearest tilt spinblock for rotor "..ix..".")
                else
                    --  Initialize our spinner if necessary.
                    if (type(vehicle.tiltRotors[lowestDistIndex]) ~= "table") then
                        local spinnerInfo = I:GetSpinnerInfo(lowestDistIndex)
                        local spinnerDetails = {info = spinnerInfo, rotors = {}, upVector = getUpVectorFromRotation(spinnerInfo.LocalRotation), startRotation = spinnerInfo.LocalRotation}
                        vehicle.tilts[lowestDistIndex] = spinnerDetails
                    end
                    
                    --  Put the current dedicated spinblock index into an array.
                    table.insert(vehicle.tilts[lowestDistIndex].rotors, ix)
                    table.insert(vehicle.ignoredRotors, ix)
                end
            end
        end
    end
        
    --  Check for the existence of sufficient control thrust for translation directions
    if (vehicle.hasThrust == false and thrustControls[0] and thrustControls[1] and thrustControls[2] and thrustControls[3]) then vehicle.hasThrust = true end
    if (vehicle.hasSlide == false and slideControls[0] and slideControls[1] and slideControls[2] and slideControls[3]) then vehicle.hasSlide = true end
    if (vehicle.hasLift == false and liftControls[0] and liftControls[1]) then vehicle.hasLift = true end
    I:Log("Detection done")
end

--  Update target and construct metadata
function update(I)
    if (vehicle.docked ~= true) then
        --  Get raw vehicle data
        vehicle.position = I:GetConstructPosition()
        vehicle.roll = I:GetConstructRoll()
        vehicle.yaw = I:GetConstructYaw()
        vehicle.pitch = I:GetConstructPitch()
        vehicle.heading = I:GetConstructForwardVector()
        vehicle.velocity = I:GetVelocityVector()
        vehicle.velocityMagnitude = I:GetVelocityMagnitude()
        vehicle.forwardsVelocity = I:GetForwardsVelocityMagnitude()
        
        --  Calculate the slide velocity of the vehicle
        local tmpHeading = vehicle.heading
        local tmpVelocity = vehicle.velocity
        tmpHeading.y = 0
        tmpVelocity.y = 0
        local velocityAngle = I:Maths_AngleBetweenVectors(tmpHeading, tmpVelocity)
        
        local slideDirection = vehicle.heading.x * vehicle.velocity.z - vehicle.heading.z * vehicle.velocity.x
        if (slideDirection > 0) then slideDirection = 1
        elseif (slideDirection < 0) then slideDirection = -1 end
        
        vehicle.slideVelocity = vehicle.velocityMagnitude * velocityAngle * slideDirection / 90
        
        --  Transform pitch, roll, and yaw data from 0 to 360 range into -180 to 180
        if (vehicle.pitch > 180) then 
            vehicle.pitch = 360 - vehicle.pitch
        elseif (vehicle.pitch > 0) then
            vehicle.pitch = -vehicle.pitch 
        end
        
        if (vehicle.roll > 180) then
            vehicle.roll = 360 - vehicle.roll
        elseif (vehicle.roll > 0) then
            vehicle.roll = -vehicle.roll
        end
        
        if (vehicle.yaw > 180) then
            vehicle.yaw = 360 - vehicle.yaw
        elseif (vehicle.yaw > 0) then
            vehicle.yaw = -vehicle.yaw
        end
        
        --  Detect if vehicle is upside-down and invert controls
        vehicle.inverted = 1
        if (vehicle.roll > 90 or vehicle.roll < -90 or vehicle.pitch > 90 or vehicle.pitch < -90) then
            vehicle.inverted = -1
        end
        
        --  Execute mainframe-specific tasks if a mainframe is present, else disable targeting
        vehicle.hasTarget = false
        targets = {}
        
        if (vehicle.mainframes > 0) then
            local numTargets = I:GetNumberOfTargets(0)
            local ix = 0
            
            for ix = 0, numTargets - 1 do
                targets[ix] = I:GetTargetPositionInfo(0, ix)
                vehicle.hasTarget = true
            end
        end
        
        --  Attempt to predict terrain height in the direction of our current velocity if the option is enabled.
        if (settings.enableTerrainAvoidance) then
            local ix = 0
            vehicle.terrainPrediction = 0
            for ix = 0,settings.terrainAvoidanceSamples - 1 do
                local sample = I:GetTerrainAltitudeForLocalPosition(vehicle.velocity * ix * settings.terrainAvoidanceLookahead / (settings.terrainAvoidanceSamples - 1))
                if (sample > vehicle.terrainPrediction) then
                    vehicle.terrainPrediction = sample
                end
            end
        end
        
        vehicle.lastHealth = I:GetHealthFraction()
    end
end

--  Determines control outputs for thrusters and spinblocks
function control(I)
    if (vehicle.docked) then
        output.thrust = 0
        output.slide = 0
        output.altitude = 0
        output.roll = 0
        output.pitch = 0
        output.yaw = 0
    else
        local targetPitch, targetRoll, targetYaw, targetThrust, targetSlide, targetAltitude = 0, 0, 0, 0, 0, 0
        local curPitch, curRoll, curYaw, curThrust, curSlide, curAltitude = 0, 0, 0, 0, 0, 0
        
        curRoll = vehicle.roll
        curPitch = vehicle.pitch
        curYaw = vehicle.yaw
        curThrust = vehicle.forwardsVelocity
        curSlide = vehicle.slideVelocity
        curAltitude = vehicle.position.y
        
        --  Calculate the minimum desired altitude based on terrain
        if (settings.enableTerrainAvoidance) then
            local minHeight = 0
            if (settings.maxRoll > 0) then minHeight = minHeight + vehicle.size.z * (settings.maxRoll / 90) end
            
            if (settings.terrainRestrictSeaLevel) then
                targetAltitude = clamp(vehicle.terrainPrediction + settings.minAltitude + vehicle.size.y / 2, settings.minAltitude, settings.maxAltitude)
            else
                targetAltitude = math.max(vehicle.terrainPrediction + settings.minAltitude + vehicle.size.y / 2, settings.maxAltitude)
            end
        else
            targetAltitude = settings.targetAltitude
        end
        
        --  If no target exists, hover in place
        if (vehicle.hasTarget == false or targets[0].Valid == false) then
            curThrust = vehicle.forwardsVelocity
            curSlide = -vehicle.slideVelocity
            curYaw = 0
            
            if (vehicle.hadTarget) then
                targetYaw = vehicle.yaw
                resetPID()
                vehicle.hadTarget = false
                I:Log("Target lost. Resetting.")
            end
        --  A target exists; begin distance maintaining behavior
        else
            vehicle.ticksSinceDodge = vehicle.ticksSinceDodge + 1
            
            if (settings.enableDodging and vehicle.ticksSinceDodge > settings.dodgeFrequency / tickRate) then
                dodgeTargets = dodge(I)
                vehicle.ticksSinceDodge = 0
            end
            
            targetThrust = -settings.targetDistance
            curSlide = dodgeTargets.x
            curThrust = -targets[0].Range + dodgeTargets.z
            curYaw = targets[0].Azimuth
            vehicle.hadTarget = true
            
            if (settings.enablePitchToTarget) then
                targetPitch = targets[0].ElevationForAltitudeComponentOnly
            end
            
            if (settings.enableAltitudeMatching) then
                local altToMatch = clamp(targets[0].Position.y + dodgeTargets.y + settings.altitudeMatchingOffset, settings.minAltitude, settings.maxAltitude)
                
                if (settings.enableTerrainAvoidance == false or altToMatch >= targetAltitude) then
                    targetAltitude = altToMatch
                end
            end
        end
        
        --  Calculate thrust/slide/altitude translation control outputs
        output.thrust = clamp(PID("Thrust", targetThrust, curThrust, pidFactors.thrust), -1, 1)
        
        output.slide = clamp(PID("Slide", targetSlide, curSlide, pidFactors.slide), -1, 1)
        output.altitude = clamp(PID("Altitude", targetAltitude, curAltitude, pidFactors.altitude), -1, 1)

        --  Calculate rotations necessary to achieve translation if no translation thrusters are available in a given direction.
        if (vehicle.hasThrust == false) then
            targetPitch = -output.thrust
        end
        
        if (vehicle.hasSlide == false) then
            targetRoll = output.slide * settings.maxRoll
        end
        
        --  Calculate roll/pitch/yaw angle control outputs
        output.roll = -clamp(PID("Roll", targetRoll, curRoll, pidFactors.roll), -1, 1)
        output.pitch = clamp(PID("Pitch", targetPitch, curPitch, pidFactors.pitch), -1, 1)
        output.yaw = clamp(PID("Yaw", targetYaw, curYaw, pidFactors.yaw), -1, 1)
        
        if (settings.enableDodging) then
            dodge(I)
        end
    end
end

function dodge(I)
    local dodgeMove = {x = 0, y = 0, z = 0}
    
    dodgeMove.x = math.random(-vehicle.size.x, vehicle.size.x) * settings.dodgeMultiplier.x
    dodgeMove.y = math.random(-vehicle.size.y, vehicle.size.y) * settings.dodgeMultiplier.y
    dodgeMove.z = math.random(-vehicle.size.z, vehicle.size.z) * settings.dodgeMultiplier.z
    
    return dodgeMove
end

--  Decides how to use thrusters and spinblocks to achieve desired control, and fires control inputs
function thrust(I)
    local ix = 0
    
    --  Manage hull-mounted thrusters
    for ix = 0, #vehicle.thrusters - 1 do
        local totalThrust = 0
        
        if (vehicle.docked ~= true) then
            local info = vehicle.thrusters[ix]

            --  If pointing up or down, use for vertical thrust, pitch, and roll
            if (info.LocalForwards.y > .95 or info.LocalForwards.y < -.95) then
                local verticalFactor = info.LocalForwards.y
                
                totalThrust = clamp(output.altitude * verticalFactor * vehicle.inverted, -1, 1) * settings.maxLiftPercentage
                totalThrust = totalThrust + 2 * info.LocalPositionRelativeToCom.x * verticalFactor * output.roll / vehicle.size.x
                totalThrust = totalThrust + 2 * info.LocalPositionRelativeToCom.z * verticalFactor * output.pitch / vehicle.size.z
                
            --  If pointing left or right, use for lateral thrust, yaw, and roll
            elseif (info.LocalForwards.x > .95 or info.LocalForwards.x < -.95) then
                local slideFactor = info.LocalForwards.x
                
                totalThrust = clamp(output.slide * slideFactor * vehicle.inverted, -1, 1) * settings.maxSlidePercentage
                totalThrust = totalThrust + 2 * info.LocalPositionRelativeToCom.y * slideFactor * output.roll / vehicle.size.y
                totalThrust = totalThrust + 2 * info.LocalPositionRelativeToCom.z * slideFactor * output.yaw / vehicle.size.z
            --  If pointing forwards or back, use for forwards/reverse thrust, yaw, and pitch
            elseif (info.LocalForwards.z > .95 or info.LocalForwards.z < -.95) then
                local thrustFactor = info.LocalForwards.z
                
                totalThrust = clamp(output.thrust * thrustFactor * vehicle.inverted, -1, 1) * settings.maxThrustPercentage
                --totalThrust = thrustControl + 2 * info.LocalPositionRelativeToCom.y * thrustFactor * pitchControl / size.y
                --totalThrust = thrustControl + 2 * info.LocalPositionRelativeToCom.x * thrustFactor * yawControl / size.x
            end
            
            totalThrust = clamp(totalThrust, -1, 1)
        end
        
        I:Component_SetFloatLogic(CONST.THRUSTER, ix, totalThrust)
    end
    
    --  Manage hull-mounted rotors
    local spinner = {}
    for ix,spinner in pairs(vehicle.spinners) do
        local ignoreThisRotor = false
        for iy,val in pairs(vehicle.ignoredRotors) do
            if (val == ix) then ignoreThisRotor = true end
        end
        
        if (ignoreThisRotor == false) then
            local totalSpeed = 0
            
            if (vehicle.docked ~= true) then
                --  If pointing up or down, use for vertical thrust, pitch, and roll
                if (spinner.upVector.y > .95 or spinner.upVector.y < -.95) then
                    local verticalFactor = spinner.upVector.y 
                    
                    totalSpeed = clamp(output.altitude * verticalFactor * vehicle.inverted, -1, 1) * settings.maxLiftPercentage
                    totalSpeed = totalSpeed + 2 * spinner.info.LocalPositionRelativeToCom.x * verticalFactor * output.roll / vehicle.size.x
                    totalSpeed = totalSpeed + 2 * spinner.info.LocalPositionRelativeToCom.z * verticalFactor * output.pitch / vehicle.size.z
                    
                --  If pointing left or right, use for lateral thrust, yaw, and roll
                elseif (spinner.upVector.x > .95 or spinner.upVector.x < -.95) then
                    local slideFactor = spinner.upVector.x
                    
                    totalSpeed = clamp(output.slide * slideFactor * vehicle.inverted, -1, 1) * settings.maxSlidePercentage
                    totalSpeed = totalSpeed + 2 * spinner.info.LocalPositionRelativeToCom.y * slideFactor * output.roll / vehicle.size.y
                    totalSpeed = totalSpeed + 2 * spinner.info.LocalPositionRelativeToCom.z * slideFactor * output.yaw / vehicle.size.z
                --  If pointing forwards or back, use for forwards/reverse thrust, yaw, and pitch
                elseif (spinner.upVector.z > .95 or spinner.upVector.z < -.95) then
                    local thrustFactor = spinner.upVector.z
                    
                    totalSpeed = clamp(output.thrust * thrustFactor * vehicle.inverted, -1, 1) * settings.maxThrustPercentage
                    --totalSpeed = thrustControl + 2 * spinner.info.LocalPositionRelativeToCom.y * thrustFactor * output.pitch / vehicle.size.y
                    totalSpeed = totalSpeed - 2 * spinner.info.LocalPositionRelativeToCom.x * thrustFactor * output.yaw / vehicle.size.x
                end
            end
            
            I:SetSpinnerContinuousSpeed(ix, totalSpeed * CONST.SPINNERSPEED)
        end
    end
    
    --  Manage tilt rotors
    local iy = 0
    local rotor = -1
    
    for ix,spinner in pairs(vehicle.tilts) do
        local tilt = 0
        local thrust = 0
        local tiltDirection = -1
        local upDirection = 1
        
        if (vehicle.docked ~= true) then
            spinnerInfo = I:GetSpinnerInfo(ix)
            if (spinnerInfo ~= nil) then
                local currentRotation = getEulerAngles(Quaternion.Inverse(spinner.startRotation) * spinnerInfo.LocalRotation)
                
                if (spinner.upVector.x < -.95) then upDirection = -1 end
                if (spinner.info.LocalPositionRelativeToCom.x < 0) then tiltDirection = tiltDirection * -1 end
                tiltDirection = upDirection * tiltDirection
                
                if (spinner.upVector.x < -.95 or spinner.upVector.x > .95) then currentRotation = currentRotation.y
                elseif (spinner.upVector.y < -.95 or spinner.upVector.y > .95) then currentRotation = currentRotation.z
                elseif (spinner.upVector.z < -.95 or spinner.upVector.z > .95) then currentRotation = currentRotation.x end
                
                tilt = math.deg(output.yaw * tiltDirection + output.thrust * upDirection)
                
                tilt = clamp(PID("RotorTilt-"..ix, tilt, currentRotation, pidFactors.rotorTilt), -1, 1) * settings.maxRotorTilt
                
                thrust = clamp(output.altitude * vehicle.inverted, -1, 1) * settings.maxLiftPercentage
                thrust = thrust + spinner.info.LocalPositionRelativeToCom.x * output.roll / vehicle.size.x
                thrust = thrust + spinner.info.LocalPositionRelativeToCom.z * output.pitch / vehicle.size.z
            end
        end
        
        for iy,rotor in pairs(spinner.rotors) do
            local details = I:GetSpinnerInfo(rotor)
            local upVector = getUpVectorFromRotation(details.LocalRotation)
            local thrustInversion = 1
            
            if (upVector.y < -.95) then thrustInversion = -1 end
            --I:Log(rotor..' '..upVector.y..' '..thrust..' '..details.Position.x - vehicle.position.x)
            I:SetSpinnerContinuousSpeed(rotor, thrust * CONST.SPINNERSPEED)
        end
        
        I:SetSpinnerRotationAngle(ix, tilt)
    end
    
    --  Force all thrust output to fire at full strength
    I:RequestControl(CONST.AIR, CONST.YAWLEFT, 1)
    I:RequestControl(CONST.AIR, CONST.YAWRIGHT, 1)
    I:RequestControl(CONST.AIR, CONST.ROLLLEFT, 1)
    I:RequestControl(CONST.AIR, CONST.ROLLRIGHT, 1)
    I:RequestControl(CONST.AIR, CONST.NOSEUP, 1)
    I:RequestControl(CONST.AIR, CONST.NOSEDOWN, 1)
    I:RequestControl(CONST.AIR, CONST.INCREASE, 1)
    I:RequestControl(CONST.AIR, CONST.DECREASE, 1)
    I:RequestControl(CONST.AIR, CONST.MAIN, 1)
end

--  Returns a set of Euler angles for yaw, pitch, and roll from a quaternion
function getEulerAngles(quat)
    local x2 = quat.x * quat.x
    local y2 = quat.y * quat.y
    local z2 = quat.z * quat.z
    local w2 = quat.w * quat.w
    
    local correction = x2 + y2 + z2 + w2
    local test = quat.x * quat.y + quat.z * quat.w
    local yaw,pitch,roll
    
    --  Deal with gimbal problems
    if (test > .49999 * correction) then
        yaw = 2 * math.atan2(quat.x, quat.w)
        pitch = math.pi / 2
        roll = 0
    elseif (test < -4.9999 * correction ) then
        yaw = -2 * math.atan2(quat.x, quat.w)
        pitch = -math.pi / 2
        roll = 0
    else
        yaw = math.atan2(2 * quat.y * quat.w - 2 * quat.x * quat.z, x2 - y2 - z2 + w2)
        pitch = math.asin(2 * test / correction)
        roll = math.atan2(2 * quat.x * quat.w - 2 * quat.y * quat.z, -x2 + y2 - z2 + w2)
    end
    
    return Vector3(math.deg(pitch), math.deg(yaw), math.deg(roll))
end

-- Thanks to Evil4Zerggin for the math behind this function
function getUpVectorFromRotation(quat)
    local x = 2 * (quat.x * quat.y - quat.z * quat.w)
    local y = 1 - 2 * (quat.x * quat.x + quat.z * quat.z)
    local z = 2 * (quat.y * quat.z + quat.x * quat.w)
    
    return Vector3(x, y, z).normalized
end

--  Performs a PID transform, indexed by name. Target is the desired value, current is the measured value, factors is an array with
--     proportional, integral, and derivative term factors, in that order
function PID(name, target, current, factors)
    if (prevErrors[name] == nil) then prevErrors[name] = 0 end
    if (integrals[name] == nil) then integrals[name] = 0 end
    
    local err = target - current
    local derivative = (err - prevErrors[name]) / tickRate
    local out = factors[1] * err + factors[2] * integrals[name] * tickRate + factors[3] * derivative

    integrals[name] = integrals[name] + err * tickRate
    prevErrors[name] = err

    return out
end

--  Resets all PID parameters to let it relearn
function resetPID()
    prevErrors = {}
    integrals = {}
end

--  Returns the input, min if input is less than min, or max if input is greater than max
function clamp(input, minVal, maxVal)
    return math.min(math.max(input, minVal), maxVal)
end