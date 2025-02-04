/*
	Drone class

	Main object for interacting with the drones.  Instantiated by obj_Ship, only.

	-- CyberTech

*/

objectdef obj_Drones inherits obj_BaseClass
{

	variable index:int64 ActiveDroneIDList
	variable int CategoryID_Drones = 18
	variable int LaunchedDrones = 0
	variable int WaitingForDrones = 0
	variable bool DronesReady = FALSE
	variable int ShortageCount

	variable int64 MiningDroneTarget=0
	variable obj_PulseTimer DroneReturnTimer

	method Initialize()
	{
		LogPrefix:Set["${This.ObjectName}"]

		PulseTimer:SetIntervals[2.0,4.0]
		Event[EVENT_EVEBOT_ONFRAME]:AttachAtom[This:Pulse]

		DroneReturnTimer:SetIntervals[3.0,4.0]
		Logger:Log["${LogPrefix}: Initialized", LOG_MINOR]
	}

	method Shutdown()
	{
		Event[EVENT_EVEBOT_ONFRAME]:DetachAtom[This:Pulse]
		if ${Me.InSpace}
		{
			if (${Me.ToEntity.Mode} != 3)
			{
				Logger:Log["Recalling Drones prior to shutdown..."]
				EVE:Execute[CmdDronesReturnToBay]
			}
		}
	}

	method Pulse()
	{
		if !${EVEBot.Loaded} || ${EVEBot.Disabled}
		{
			return
		}

		if ${This.WaitingForDrones}
		{
			if ${This.PulseTimer.Ready}
			{
				if !${EVEBot.Paused}
				{
					if ${Me.InSpace}
					{
						This.WaitingForDrones:Dec
						This.LaunchedDrones:Set[${This.DronesInSpace}]
						if  ${This.LaunchedDrones} > 0
						{
							This.WaitingForDrones:Set[0]
							This.DronesReady:Set[TRUE]
							Logger:Log["${LogPrefix}: Deployed ${This.LaunchedDrones} drones"]
						}

					}
				}

				This.PulseTimer:Update
			}
		}
	}

	method LaunchAll(string Caller)
	{
		if ${This.WaitingForDrones} || !${This.DroneReturnTimer.Ready}
		{
			return
		}

		if ${This.DronesInBay} > 0 && !${This.AreMaxDronesActive}
		{
			Logger:Log["${Caller}: Launching drones - Bay: ${This.DronesInBay}, Active: ${This.DronesInSpace}, Possible: ${Me.MaxActiveDrones}"]
			MyShip:LaunchAllDrones
			This.WaitingForDrones:Set[5]
		}
	}

	member:bool AreMaxDronesActive()
	{
		if ${This.DronesInSpace} < ${Me.MaxActiveDrones}
		{
			return FALSE
		}

		return TRUE
	}

	member:int DronesInBay()
	{
		variable int count
		variable index:item DroneList
		MyShip:GetDrones[DroneList]
		DroneList:ForEach["count:Inc[\${ForEach.Value.Quantity}]"]
		return ${count}
	}

	member:int DronesInSpace(bool IncludeFighters=TRUE)
	{
		Me:GetActiveDroneIDs[This.ActiveDroneIDList]
		if !${IncludeFighters}
		{
			This.ActiveDroneIDList:RemoveByQuery[${LavishScript.CreateQuery[GroupID = GROUP_FIGHTERDRONE]}]
		}
		return ${This.ActiveDroneIDList.Used}
	}

	member:bool CombatDroneShortage()
	{
		if !${This.DronesReady}
		{
			return
		}

		if (${MyShip.DronebayCapacity} > 0 && \
   			${This.DronesInBay} == 0 && \
   			${This.DronesInSpace} < ${Config.Combat.MinimumDronesInSpace})
   		{
			ShortageCount:Inc
   			if ${ShortageCount} > 10
   			{
   				return TRUE
   			}
   		}
   		else
   		{
   			ShortageCount:Set[0]
   		}
   		return FALSE
	}

	; Returns the number of Drones in our station hanger.
	member:int DronesInStation()
	{
		return ${Station.DronesInStation.Used}
	}

	function StationToBay()
	{
		if ${This.DronesInStation} == 0 || \
			!${MyShip(exists)}
		{
			return
		}

		EVE:Execute[OpenDroneBayOfActiveShip]
		wait 15

		variable iterator CargoIterator
		Station.DronesInStation:GetIterator[CargoIterator]

		if ${CargoIterator:First(exists)}
		do
		{
			;Logger:Log["obj_Drones:TransferToDroneBay: ${CargoIterator.Value.Name}"]
			CargoIterator.Value:MoveTo[${MyShip.ID}, DroneBay,1]
			wait 30
		}
		while ${CargoIterator:Next(exists)}
		wait 10
		EVEWindow[MyDroneBay]:Close
		wait 10
	}


	method ReturnAllToDroneBay(string Caller, string Reason)
	{
		if !${DroneReturnTimer.Ready}
		{
			;Logger:Log["${LogPrefix} ReturnAllToDroneBay called too often: ${Caller} - ${Reason}", LOG_DEBUG]
			return
		}
		if ${This.DronesInSpace[FALSE]} > 0
		{
			Logger:Log["${Caller}: Recalling ${This.ActiveDroneIDList.Used} Drones - ${Reason}"]
			This.ActiveDroneIDList:RemoveByQuery[${LavishScript.CreateQuery[GroupID = GROUP_FIGHTERDRONE]}]
			EVE:DronesReturnToDroneBay[This.ActiveDroneIDList]
			DroneReturnTimer:Update
		}
	}

	method ActivateMiningDrones()
	{
		if !${This.DronesReady}
		{
			return
		}

		if (${This.DronesInSpace} > 0)
		{
			Logger:Log["Debug: Drones ordered to mine ${Me.ActiveTarget.ID}", LOG_DEBUG]
			EVE:DronesMineRepeatedly[This.ActiveDroneIDList]
			MiningDroneTarget:Set[${Me.ActiveTarget}]
		}
	}

	member:bool IsMiningAsteroidID(int64 EntityID)
	{
		if ${MiningDroneTarget} == ${EntityID}
		{
			return TRUE
		}
		return FALSE
	}

	method SendDrones()
	{
		if !${This.DronesReady}
		{
			return
		}

		if (${This.DronesInSpace} > 0)
		{
			variable iterator DroneIterator
			variable index:activedrone ActiveDroneList
			Me:GetActiveDrones[ActiveDroneList]
			ActiveDroneList:GetIterator[DroneIterator]
			variable index:int64 returnIndex
			variable index:int64 engageIndex

			do
			{
				if ${DroneIterator.Value.ToEntity.GroupID} != GROUP_FIGHTERDRONE && \
					(${DroneIterator.Value.ToEntity.ShieldPct} < 80 || \
					${DroneIterator.Value.ToEntity.ArmorPct} < 0)
				{
					if ${DroneReturnTimer.Ready}
					{
						Logger:Log["Recalling Damaged Drone ${DroneIterator.Value.ID} Shield %: ${DroneIterator.Value.ToEntity.ShieldPct} Armor %: ${DroneIterator.Value.ToEntity.ArmorPct}"]
						returnIndex:Insert[${DroneIterator.Value.ID}]
					}
				}
				else
				{
					if (${DroneIterator.Value.State} == 0)
					{
					Logger:Log["Debug: Drone ${DroneIterator.Value.ID} engaging current target", LOG_DEBUG]
					engageIndex:Insert[${DroneIterator.Value.ID}]
					}
				}
			}
			while ${DroneIterator:Next(exists)}
			if ${returnIndex.Used} > 0
			{
				EVE:DronesReturnToDroneBay[returnIndex]
				DroneReturnTimer:Update
			}
			if ${engageIndex.Used} > 0
			{
				EVE:Execute[CmdDronesEngage]
				;EVE:DronesEngageMyTarget[engageIndex]
			}
		}
	}
}
