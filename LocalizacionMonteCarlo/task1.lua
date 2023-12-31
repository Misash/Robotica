-- Generate a sample from a Gaussian distribution
function gaussian (mean, variance)
    return  math.sqrt(-2 * variance * math.log(math.random())) *
            math.cos(2 * math.pi * math.random()) + mean
end


function createRandomBumpyFloor()
    print ("Generating new random bumpy floor.")
    sim.setThreadAutomaticSwitch(false)

    -- Remove existing bumpy floor if there already is one
    if (heightField ~= nil) then
        sim.setObjectPosition(heightField, heightField, {0.05, 0, 0})
        return
    end
    --  Create random bumpy floor for robot to drive on
    floorSize = 5
    --heightFieldResolution = 0.3
    --heightFieldNoise = 0.00000005
    heightFieldResolution = 0.1
    heightFieldNoise = 0.0000008
    cellsPerSide = floorSize / heightFieldResolution
    cellHeights = {}
    for i=1,cellsPerSide*cellsPerSide,1 do
        table.insert(cellHeights, gaussian(0, heightFieldNoise))
    end
    heightField=sim.createHeightfieldShape(0, 0, cellsPerSide, cellsPerSide, floorSize, cellHeights)
    -- Make the floor invisible
    sim.setObjectInt32Param(heightField,10,0)
    sim.setThreadAutomaticSwitch(true)
end


function get_walls()
    -- Disable error reporting
    local savedState=sim.getInt32Param(sim.intparam_error_report_mode)
    sim.setInt32Param(sim.intparam_error_report_mode,0)
    local N = 1
    while true do
        local handle = sim.getObjectHandle("Wall"..tostring(N))
        if handle <= 0 then
            break
        end

        -- Read position and shape of wall
        -- Assume here that it is thin and oriented either along the x axis or y axis

        -- We can now get the propertries of these walls, e.g....
        local pos = sim.getObjectPosition(handle, -1)
        local res,minx = sim.getObjectFloatParameter(handle,15)
        local res,maxx = sim.getObjectFloatParameter(handle,18)
        local res,miny = sim.getObjectFloatParameter(handle,16)
        local res,maxy = sim.getObjectFloatParameter(handle,19)

        --print("Position of Wall " .. tostring(N) .. ": " .. tostring(pos[1]) .. "," .. tostring(pos[2]) .. "," .. tostring(pos[3]))
        --print("minmax", minx, maxx, miny, maxy)

        local Ax, Ay, Bx, By
        if (maxx - minx > maxy - miny) then
            print("Wall " ..tostring(N).. " along x axis")
            Ax = pos[1] + minx
            Ay = pos[2]
            Bx = pos[1] + maxx
            By = pos[2]
        else
            print("Wall " ..tostring(N).. " along y axis")
            Ax = pos[1]
            Ay = pos[2] + miny
            Bx = pos[1]
            By = pos[2] + maxy
        end
        print (Ax, Ay, Bx, By)

        walls[N] = {Ax, Ay, Bx, By}
        N = N + 1
    end
    -- enable error reporting
    sim.setInt32Param(sim.intparam_error_report_mode,savedState)

    return N - 1
end


-- This function is executed exactly once when the scene is initialised
function sysCall_init()
    tt = sim.getSimulationTime()
    print("Init hello", tt)

    robotBase=sim.getObjectHandle(sim.handle_self) -- robot handle
    leftMotor=sim.getObjectHandle("leftMotor") -- Handle of the left motor
    rightMotor=sim.getObjectHandle("rightMotor") -- Handle of the right motor
    turretMotor=sim.getObjectHandle("turretMotor") -- Handle of the turret motor
    turretSensor=sim.getObjectHandle("turretSensor")
 
    -- Create bumpy floor for robot to drive on
    createRandomBumpyFloor()

    -- Usual rotation rate for wheels (radians per second)
    speedBase = 5
    speedBaseL = 0
    speedBaseR = 0

    -- Which step are we in?
    -- 0 is a dummy value which is immediately completed
    stepCounter = 0
    stepCompletedFlag = false

    -- Sequential state machine (executed for each waypoint)
    stepList = {}
    stepList[1] = {"read_waypoint"}
    stepList[2] = {"turn"}
    stepList[3] = {"stop"}
    stepList[4] = {"forward"}
    stepList[5] = {"stop"}
    stepList[6] = {"repeat"}

    -- Waypoints
    N_WAYPOINTS = 26
    currentWaypoint = 1
    waypoints = {}
    waypoints[1] = {0.5,0}
    waypoints[2] = {1,0}
    waypoints[3] = {1,0.5}
    waypoints[4] = {1,1}
    waypoints[5] = {1,1.5}
    waypoints[6] = {1,2}
    waypoints[7] = {0.5,2}
    waypoints[8] = {0,2}
    waypoints[9] = {-0.5,2}
    waypoints[10] = {-1,2}
    waypoints[11] = {-1,1.5}
    waypoints[12] = {-1,1}
    waypoints[13] = {-1.5,1}
    waypoints[14] = {-2,1}
    waypoints[15] = {-2,0.5}
    waypoints[16] = {-2,0}
    waypoints[17] = {-2,-0.5}
    waypoints[18] = {-1.5,-1}
    waypoints[19] = {-1,-1.5}
    waypoints[20] = {-0.5,-1.5}
    waypoints[21] = {0,-1.5}
    waypoints[22] = {0.5,-1.5}
    waypoints[23] = {1,-1.5} 
    waypoints[24] = {1,-1}
    waypoints[25] = {0.5,-0.5}
    waypoints[26] = {0,0}

    -- Create and initialise arrays for particles, and display them with dummies
    xArray = {}
    yArray = {}
    thetaArray = {}
    weightArray = {}
    dummyArray = {}
    numberOfParticles = 100
    -- Initialise all particles to origin with uniform distribution
    -- We have certainty about starting position
    for i=1, numberOfParticles do
        xArray[i] = 0
        yArray[i] = 0
        -- ynew = 0 + (D+e)sin(0) will always give 0
        -- This is unrealistic but can be mitigated by initialising theta to a tiny
        -- bit of zero mean noise rather than to 0
        -- This would not be a problem in realistic scenarios as you could never be
        -- a 100% certain that you positioned your robot with an exact orientation
        thetaArray[i] = gaussian(0, 0.002)
        weightArray[i] = 1.0/numberOfParticles
        dummyArray[i] = sim.createDummy(0.05) -- Returns integer object handle

        -- Args: object handle, reference frame (-1 = absolute position), coordinates (x,y,z)
        sim.setObjectPosition(dummyArray[i], -1, {xArray[i],yArray[i],0})
        -- Args: object handle, reference frame (-1 = absolute position), euler angles (alpha, beta, gamma)
        sim.setObjectOrientation(dummyArray[i], -1, {0,0,thetaArray[i]})
    end

    -- Target movements for reaching the current waypoint
    waypointRotationRadians = 0.0
    waypointDistanceMeter = 0.0

    -- Target positions for joints
    motorAngleTargetL = 0.0
    motorAngleTargetR = 0.0

    -- Data structure for walls
    walls = {}
    -- Fill it by parsing the scene in the GUI
    N_WALLS = get_walls() -- Modifis "walls" and returns number of walls
    -- walls now is an array of arrays with the {Ax, Ay, Bx, By} wall coordinates

    sensorStandardDeviation = 0.1
    sensorVariance = sensorStandardDeviation^2
    noisyDistance = 0

     -- Motor angles in radians per unit (to calibrate)
    motorAnglePerMetre = 24.8
    motorAnglePerRadian = 3.05

    -- Zero mean Gaussian noise variance in meter/radians (to calibrate)
    -- Determined for a one meter distance
    straightLineXYVariance = 0.0010
    straightLineThetaVariance = 0.0010
    -- Zero mean Gaussian noise variance in radians (to calibrate)
    -- Determined for a one radian rotation
    rotationThetaVariance = 0.004
end

function sysCall_sensing()
    
end


function updateParticleVisualisation()
    for i=1, numberOfParticles do
       -- Args: object handle, reference frame (-1 = absolute position), coordinates (x,y,z)
        sim.setObjectPosition(dummyArray[i], -1, {xArray[i],yArray[i],0.0})
        -- Args: object handle, reference frame (-1 = absolute position), euler angles (alpha, beta, gamma)
        sim.setObjectOrientation(dummyArray[i], -1, {0.0,0.0,thetaArray[i]})
    end
end


-- Performs a particle motion prediction update for straight line motion.
-- Does not do anything if 'metersMovedSinceLastUpdate' is zero (robot did not do anything).
function updateParticlesAfterStraightLineMotion(metersMovedSinceLastUpdate)
    -- Don't increase uncertainty if we did not do a movement
    if (metersMovedSinceLastUpdate == 0) then
        return
    end

    for i=1, numberOfParticles do
        -- Scale variances appropriately (variance is additive and determined for one meter)
        local distanceNoise = gaussian(0, straightLineXYVariance * metersMovedSinceLastUpdate)
        local rotationNoise = gaussian(0, straightLineThetaVariance * metersMovedSinceLastUpdate)

        local noisyDistance = metersMovedSinceLastUpdate + distanceNoise
        local noisyDistanceX = noisyDistance * math.cos(thetaArray[i])
        local noisyDistanceY = noisyDistance * math.sin(thetaArray[i])

        xArray[i] = xArray[i] + noisyDistanceX
        yArray[i] = yArray[i] + noisyDistanceY
        thetaArray[i] = thetaArray[i] + rotationNoise
    end

    updateParticleVisualisation()

    print("Updated particles after straight line motion")
end


-- Performs a particle motion prediction update for pure rotation (rotation on the spot).
-- Does not do anything if 'radiansRotatedSinceLastUpdate' is zero (robot did not do anything).
function updateParticlesAfterPureRotation(radiansRotatedSinceLastUpdate)
    -- Don't increase uncertainty if we did not do a movement
    if (radiansRotatedSinceLastUpdate == 0) then
        return
    end

    for i=1, numberOfParticles do
        -- Scale variance appropriately (variance is additive and determined for one radian)
        local rotationNoise = gaussian(0, rotationThetaVariance * math.abs(radiansRotatedSinceLastUpdate))

        local noisyRoationRadians = radiansRotatedSinceLastUpdate + rotationNoise
        thetaArray[i] = thetaArray[i] + noisyRoationRadians
    end

    updateParticleVisualisation()

    print("Updated particles after pure rotation")
end


-- Euclidean distance between two points
function euclideanDistance(x1, y1, x2, y2)
    return math.sqrt((x1-x2)^2 + (y1-y2)^2)
end


-- Returns true if the point (x, y) lies on the line between two points (Ax, Ay) and (Bx, By).
function isPointOnLineBetweenTwoPoints(x, y, Ax, Ay, Bx, By)
    local distanceMargin = 0.01 -- Needed for floating point errors
    return math.abs(euclideanDistance(Ax, Ay, x, y) + euclideanDistance(x, y, Bx, By) - euclideanDistance(Ax, Ay, Bx, By)) < distanceMargin
end


-- (x, y, theta) is the hypthosesis of a single particle.
-- z is the sonar distance measurement.
function calculateLikelihood(x, y, theta, z)
    -- Compute expected depth measurement m, assuming robot pose (x, y, theta)
    local m = math.huge
    for _, wall in ipairs(walls) do
        Ax = wall[1]
        Ay = wall[2]
        Bx = wall[3]
        By = wall[4]

        local distanceToWall = ((By - Ay)*(Ax - x) - (Bx - Ax)*(Ay - y)) / ((By - Ay)*math.cos(theta) - (Bx - Ax)*math.sin(theta))

        if (distanceToWall < m and distanceToWall >= 0) then
            -- Check if the sonar should hit between the endpoint limits of the wall
            local intersectX = x + distanceToWall * math.cos(theta)
            local intersectY = y + distanceToWall * math.sin(theta)

            -- Only update m if the sonar would actually hit the wall
            if (isPointOnLineBetweenTwoPoints(intersectX, intersectY, Ax, Ay, Bx, By)) then
                m = distanceToWall
            end
        end
    end

    -- Compute likelihood based on difference between m and z
    local likelihood = math.exp(- (z - m)^2 / (2*sensorVariance))

    if (m == math.huge) then
        print("NO ACTUAL DISTANCE TO WALL FOUND: Assume likelihood is one")
        likelihood = 1.0
    end

    return likelihood
end


-- Returns the sum of all elements in an array.
function sum(array)
    local sum = 0
    for i=1, #array do
        sum = sum + array[i]
    end

    return sum
end


-- Perform particle filter normalisation step to ensure that weights add up to 1.
function normaliseParticleWeights()
    local weightSum = sum(weightArray)
    for i=1, #weightArray do
        weightArray[i] = weightArray[i] / weightSum
    end
end


-- Perform particle resampling using biased roulette wheel method.
function resampleParticles()
    local cumulativeWeightArray = {weightArray[1]}
    for i=2, numberOfParticles do
        cumulativeWeightArray[i] = cumulativeWeightArray[i-1] + weightArray[i]
    end

    local newXArray = {}
    local newYArray = {}
    local newThetaArray = {}
    for i=1, numberOfParticles do
        local r = math.random() -- Random number in range [0,1]
        for j=1, #cumulativeWeightArray do
            if (r <= cumulativeWeightArray[j]) then
                newXArray[i] = xArray[j]
                newYArray[i] = yArray[j]
                newThetaArray[i] = thetaArray[j]
                break
            end
        end
    end

    xArray = newXArray
    yArray = newYArray
    thetaArray = newThetaArray

    for i=1, numberOfParticles do
        weightArray[i] = 1 / numberOfParticles
    end
end


-- Perform particle measurement update
function updateParticlesAfterMeasurement(distanceMeasurement)
    -- Measurement update
    for i=1, numberOfParticles do
        local likelihood = calculateLikelihood(xArray[i], yArray[i], thetaArray[i], distanceMeasurement)
        weightArray[i] = weightArray[i] * likelihood
    end

    normaliseParticleWeights()

    resampleParticles()

    updateParticleVisualisation()

    print("Updated particles after measurement update, normalisation, and resampling")
end


-- Takes an array of values and an array of corresponding weights.
-- Both arrays must be of the same length.
function weighted_sum(values, weights)
    local sum = 0.0
    for i=1, #values do
        sum = sum + weights[i] * values[i]
    end

    return sum
end


-- Transforms theta into the range -pi < deltaTheta <= pi by subtraction/addition of 2*pi
function normaliseThetaMinusPiToPlusPi(theta)
    local normalisedTheta = theta % (2.0*math.pi)
    if (normalisedTheta > math.pi) then
        normalisedTheta = normalisedTheta - 2.0*math.pi
    elseif (normalisedTheta < -math.pi) then
        normalisedTheta = normalisedTheta + 2.0*math.pi
    end

    return normalisedTheta
end


-- How far are the left and right motors from their targets? Find the maximum
function getMaxMotorAngleFromTarget(posL, posR)
    maxAngle = 0
    if (speedBaseL > 0) then
        remaining = motorAngleTargetL - posL
        if (remaining > maxAngle) then
            maxAngle = remaining
        end
    end
    if (speedBaseL < 0) then
        remaining = posL - motorAngleTargetL
        if (remaining > maxAngle) then
            maxAngle = remaining
        end
    end
    if (speedBaseR > 0) then
        remaining = motorAngleTargetR - posR
        if (remaining > maxAngle) then
            maxAngle = remaining
        end
    end
    if (speedBaseR < 0) then
        remaining = posR - motorAngleTargetR
        if (remaining > maxAngle) then
            maxAngle = remaining
        end
    end

    return maxAngle
end


function sysCall_actuation() 
    tt = sim.getSimulationTime() 

    -- Get current angles of motor joints
    posL = sim.getJointPosition(leftMotor)
    posR = sim.getJointPosition(rightMotor)

    -- Start new step?
    if (stepCompletedFlag == true or stepCounter == 0) then
        stepCounter = stepCounter + 1
        stepCompletedFlag = false

        newStepType = stepList[stepCounter][1]

        if (newStepType == "repeat") then
            -- Loop back to the first step
            stepCounter = 1
            newStepType = stepList[stepCounter][1]

            if (currentWaypoint == N_WAYPOINTS) then
                currentWaypoint = 1
            else
                currentWaypoint = currentWaypoint + 1
            end
        end

        print("New step:", stepCounter, newStepType)

        if (newStepType == "read_waypoint") then
            -- Read next waypoint
            local waypoint = waypoints[currentWaypoint]
            local goalX = waypoint[1]
            local goalY = waypoint[2]

            -- Set new movement targets to reach the new waypoint
            -- All calculations below use units meter and radian
            local currentX = weighted_sum(xArray, weightArray)
            local currentY = weighted_sum(yArray, weightArray)
            local currentTheta = weighted_sum(thetaArray, weightArray)

            local deltaX = goalX - currentX
            local deltaY = goalY - currentY
            -- Note that Lua math.atan implements atan2(dy,dx)
            local absoluteAngleToGoal = math.atan(deltaY, deltaX)
            local deltaTheta = absoluteAngleToGoal - currentTheta
            -- Make sure that -pi < deltaTheta <= pi for efficiency
            -- print("delta x", deltaX)
            -- print("delta y", deltaY)
            -- print("current theta: ", currentTheta)
            -- print("absoluteAngleToGoal: ", absoluteAngleToGoal)
            -- print("deltaTheta before optimisation: ", deltaTheta)
            deltaTheta = normaliseThetaMinusPiToPlusPi(deltaTheta)
            -- print("deltaTheta after optimisation: ", deltaTheta)

            waypointRotationRadians = deltaTheta
            waypointDistanceMeter = math.sqrt(deltaX^2 + deltaY^2)
        elseif (newStepType == "forward") then
            -- Forward step: set new joint targets
            motorAngleTargetL = posL + waypointDistanceMeter * motorAnglePerMetre
            motorAngleTargetR = posR + waypointDistanceMeter * motorAnglePerMetre
        elseif (newStepType == "turn") then
            -- Turn step: set new targets
            motorAngleTargetL = posL - waypointRotationRadians * motorAnglePerRadian
            motorAngleTargetR = posR + waypointRotationRadians * motorAnglePerRadian
        elseif (newStepType == "stop") then
            print("Stopping!!!")
        end
    end

    -- Handle current ongoing step
    stepType = stepList[stepCounter][1]

    if (stepType == "read_waypoint") then
        -- Directly move to next step
        stepCompletedFlag = true
    elseif (stepType == "turn") then
        -- Set wheel speed based on turn direction
        if (waypointRotationRadians >= 0) then
            -- Left turn
            speedBaseL = -speedBase
            speedBaseR = speedBase
        else
            -- Right turn
            speedBaseL = speedBase
            speedBaseR = -speedBase
        end

        local motorAngleFromTarget = getMaxMotorAngleFromTarget(posL, posR)
        -- Slow down when close
        if (motorAngleFromTarget < 3) then
            local speedScaling = 0.2 + 0.8 * motorAngleFromTarget / 3
            speedBaseL = speedBaseL * speedScaling
            speedBaseR = speedBaseR * speedScaling
        end
        -- Determine if we have reached the current step's goal
        if (motorAngleFromTarget == 0.0) then
            stepCompletedFlag = true

            -- Update particles
            updateParticlesAfterPureRotation(waypointRotationRadians)
            waypointRotationRadians = 0.0
        end
    elseif (stepType == "forward") then
        -- Set wheel speed
        speedBaseL = speedBase
        speedBaseR = speedBase

        local motorAngleFromTarget = getMaxMotorAngleFromTarget(posL, posR)
        -- Slow down when close
        if (motorAngleFromTarget < 3) then
            local speedScaling = 0.2 + 0.8 * motorAngleFromTarget / 3
            speedBaseL = speedBaseL * speedScaling
            speedBaseR = speedBaseR * speedScaling
        end
        -- Determine if we have reached the current step's goal
        if (motorAngleFromTarget == 0.0) then
            stepCompletedFlag = true

            -- Update particles
            updateParticlesAfterStraightLineMotion(waypointDistanceMeter)
            waypointDistanceMeter = 0.0
        end
    elseif (stepType == "stop") then
        -- Set speed to zero
        speedBaseL = 0
        speedBaseR = 0

        -- Check to see if the robot is stationary to within a small threshold
        local linearVelocity, angularVelocity = sim.getVelocity(robotBase)
        local vLin = math.sqrt(linearVelocity[1]^2 + linearVelocity[2]^2 + linearVelocity[3]^2)
        local vAng = math.sqrt(angularVelocity[1]^2 + angularVelocity[2]^2 + angularVelocity[3]^2)
        if (vLin < 0.001 and vAng < 0.01) then
            stepCompletedFlag = true

            -- Take measurement and perform measurement update
            result,cleanDistance = sim.readProximitySensor(turretSensor)
            if (result>0) then
                noisyDistance = cleanDistance + gaussian(0.0, sensorVariance)
                --print ("Depth sensor reading ", noisyDistance)

                --sleep(1) -- Wait so that we can differentiate motion and measurement updates in simulation
                updateParticlesAfterMeasurement(noisyDistance)
            end
        end
    end

    -- Set the motor velocities for the current step
    sim.setJointTargetVelocity(leftMotor,speedBaseL)
    sim.setJointTargetVelocity(rightMotor,speedBaseR)
end


function sleep(seconds)
    local t0 = os.clock()
    while os.clock() - t0 <= seconds do end
end


function sysCall_cleanup()
    --simUI.destroy(ui)
end