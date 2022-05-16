GlobalScirptData = {
     oldTable = { 'deepcopy of oil_well' },
     oil_well = {
          ['id'] = {
               id = 'integer',
               citizenid = 'string',
               position = {
                    coord = { 'table' },
                    rotation = { 'table' }
               },
               name = 'string',
               metadata = {
                    temp = 'float',
                    secduration = 'integer',
                    speed = 'integer',
                    oil_storage = 'float',
                    part_info = {
                         belt = 'float',
                         clutch = 'float',
                         polish = 'float'
                    }
               },
               state = 'bool',
               oilrig_hash = 'string'
          }
     },
     devices = {
          oilrig_storage = {
               {
                    id = 0,
                    citizenid = '',
                    name = '',
                    metadata = {
                         gasoline = 0.0,
                         crudeOil = 0.0
                    },
               }
          },
          oilrig_cdu = {
               {
                    id = 0,
                    citizenid = '',
                    metadata = {
                         temp = 0.0,
                         req_temp = 0.0,
                         state = false,
                         oil_storage = 0.0,
                    },
               }
          },
          oilrig_blender = {
               {
                    id = 0,
                    citizenid = '',
                    metadata = {},
               }
          },
     }
}

local serverUpdateInterval = 10000 --  database update interval

--class
function GlobalScirptData:startInit()
     InitilaizeAllDataByDatabaseValues_2()
end

function GlobalScirptData:initPhaseTwo(o)
     -- wont work without CreateThread
     Citizen.CreateThread(function()
          -- oil_well
          for key, value in pairs(o.oil_well) do
               self:newOilwell(value)
          end
          -- oilrig_storage
          for key, value in pairs(o.oilrig_storage) do
               self:newDevice(value, 'oilrig_storage')
          end
          -- oilrig_cdu
          for key, value in pairs(o.oilrig_cdu) do
               self:newDevice(value, 'oilrig_cdu')
          end
          -- -- oilrig_blender
          -- for key, value in pairs(o.oilrig_blender) do
          --      self:add(value)
          -- end
          self:saveThread()
          createMetadataTrackers(self.oil_well, self.devices)
     end)
end

function GlobalScirptData:newOilwell(oilwell)
     if self.oil_well[oilwell] ~= nil then
          return
     end
     local id = oilwell.id
     self.oil_well[id] = {}
     oilwell.metadata = json.decode(oilwell.metadata)
     oilwell.position = json.decode(oilwell.position)
     self.oil_well[id] = oilwell
end

function GlobalScirptData:newDevice(device, Type)
     if self.devices[Type][device.id] == nil then
          self.devices[Type][device.id] = {}
     end

     if Type == 'oilrig_storage' then
          device.metadata = json.decode(device.metadata)
          self.devices.oilrig_storage[device.id] = device
     elseif Type == 'oilrig_cdu' then
          device.metadata = json.decode(device.metadata)
          self.devices.oilrig_cdu[device.id] = device
     end
end

function GlobalScirptData:saveThread()
     CreateThread(function()
          while true do
               self.oldTable = deepcopy({
                    self.devices,
                    self.oil_well,
               })
               Wait(serverUpdateInterval)
               --- save metadata when we detected changes!
               if isTableChanged(self.oldTable, {
                    self.devices,
                    self.oil_well,
               }) == true then
                    for key, value in pairs(self.oil_well) do
                         GeneralUpdate({
                              type = 'metadata',
                              citizenid = value.citizenid,
                              oilrig_hash = value.oilrig_hash,
                              metadata = value.metadata
                         })
                    end
                    -- save storage data
                    for id, storage in pairs(self.devices.oilrig_storage) do
                         GeneralUpdate_2({
                              type = 'oilrig_storage',
                              citizenid = storage.citizenid,
                              metadata = storage.metadata
                         })
                    end
                    -- save CDU data
                    for id, storage in pairs(self.devices.oilrig_cdu) do
                         GeneralUpdate_2({
                              type = 'oilrig_cdu',
                              citizenid = storage.citizenid,
                              metadata = storage.metadata
                         })
                    end
               end
          end
     end)
end

--- wipes all data
function GlobalScirptData:wipeALL()
     self.oil_well = {}
     self.devices = {
          oilrig_storage = {},
          oilrig_cdu = {},
          oilrig_blender = {},
     }
     self.oldTable = {}
end

function GlobalScirptData:getByHash(oilrig_hash)
     for key, value in pairs(self.oil_well) do
          if value.oilrig_hash == oilrig_hash then
               return value, key
          end
     end
     return false
end

function GlobalScirptData:read(id)
     return self.oil_well[id]
end

function GlobalScirptData:readAll()
     return self.oil_well
end

function GlobalScirptData:getDeviceById(Type, id)
     return self.devices[Type][id]
end

function GlobalScirptData:getDeviceByCitizenId(Type, citizenid)
     for key, value in pairs(self.devices[Type]) do
          if value.citizenid == citizenid then
               return value
          end
     end
     return false
end

----------------------
-- Data Manipulations
----------------------

function createMetadataTrackers(oil_wells, devices)
     CreateThread(function()
          while true do
               for key, oil_well in pairs(oil_wells) do
                    DataManipulations_metadata_oil_well(oil_well)
               end
               for key, CDU in pairs(devices.oilrig_cdu) do
                    DataManipulations_metadata_CDU(CDU)
               end
               Wait(1000)
          end
     end)
end

function DataManipulations_metadata_CDU(CDU)
     if CDU.metadata.state == true then
          -- increase temp until reach requestd temp
          if CDU.metadata.req_temp > CDU.metadata.temp then
               CDU.metadata.temp = CDU.metadata.temp + 15.0
          elseif CDU.metadata.req_temp == CDU.metadata.temp then
               CDU.metadata.temp = CDU.metadata.req_temp
          end

          -- oil_storage > 1.0 min buffer
          -- CDU functions on current temp if we have something in oil_storage
          if CDU.metadata.oil_storage > 1.0 then
               -- get storage to export CDU products
               local storage = GlobalScirptData:getDeviceByCitizenId('oilrig_storage', CDU.citizenid)

               if CDU.metadata.temp < 20.0 and CDU.metadata.temp > 0.0 then
                    CDU.metadata.oil_storage = CDU.metadata.oil_storage - 0.5
               elseif CDU.metadata.temp < 150.0 and CDU.metadata.temp > 20.0 then
                    -- Butane & Propane
                    -- other gases
               elseif CDU.metadata.temp < 200.0 and CDU.metadata.temp > 150.0 then
                    -- Petrol
               elseif CDU.metadata.temp < 300.0 and CDU.metadata.temp > 200.0 then
                    -- Diesel
                    CDU.metadata.oil_storage = CDU.metadata.oil_storage - 0.75
                    storage.metadata.gasoline = storage.metadata.gasoline + 1.0
               elseif CDU.metadata.temp < 370.0 and CDU.metadata.temp > 300.0 then
                    -- Fuel Oil
               elseif CDU.metadata.temp < 400.0 and CDU.metadata.temp > 370.0 then
                    -- Lubricating oil, Parrafin Wax, Asphalt
               end
          end
     else
          if CDU.metadata.temp > 0 then
               CDU.metadata.temp = CDU.metadata.temp - 15.0
          else
               CDU.metadata.temp = 0.0
          end
     end
end

function DataManipulations_metadata_oil_well(oil_well)
     local pumpOverHeat = 327

     if oil_well.metadata.speed ~= 0 then
          oil_well.metadata.duration = oil_well.metadata.duration + 1
          oil_well.metadata.secduration = oil_well.metadata.duration
          if oil_well.metadata.temp ~= nil and pumpOverHeat >= oil_well.metadata.temp then
               oil_well.metadata.temp = tempGrowth(oil_well.metadata.temp, oil_well.metadata.speed, 'increase', pumpOverHeat)
               oil_well.metadata.temp = Round(oil_well.metadata.temp, 2)
          else
               oil_well.metadata.temp = pumpOverHeat
          end
          if oil_well.metadata.temp > 50 and oil_well.metadata.temp < (pumpOverHeat - 25) and oil_well.metadata.oil_storage <= 300 then
               oil_well.metadata.oil_storage = oil_well.metadata.oil_storage + (0.1 * (oil_well.metadata.speed / 50))
          end
     else
          -- reset duration
          if oil_well.metadata.duration ~= 0 then
               oil_well.metadata.duration = 0
          end
          -- start cooling procces
          if oil_well.metadata.secduration > 0 then
               oil_well.metadata.secduration = oil_well.metadata.secduration - 1
               oil_well.metadata.temp = tempGrowth(oil_well.metadata.temp, oil_well.metadata.speed, 'decrease', pumpOverHeat)
               oil_well.metadata.temp = Round(oil_well.metadata.temp, 2)
          elseif oil_well.metadata.secduration == 0 then
               oil_well.metadata.temp = 0
          end
     end
end

-- Storage
SendOilToStorage = function(oilrig, player)
     local citizenid = player.PlayerData.citizenid
     local storage = GlobalScirptData:getDeviceByCitizenId('oilrig_storage', citizenid)
     if storage == false then
          local state = InitStorage({
               citizenid = citizenid,
               name = player.PlayerData.name .. "'s storage",
          })
          if state == false then
               return false
          end
     end
     -- add to storage
     storage.metadata.crudeOil = Round(storage.metadata.crudeOil + oilrig.metadata.oil_storage, 2)
     -- remove from oilwell
     oilrig.metadata.oil_storage = 0.0
     return true
end

InitStorage = function(o)
     print_table(o)
     local sqlQuery = 'INSERT INTO oilrig_storage (citizenid,name,metadata) VALUES (?,?,?)'
     local QueryData = {
          o.citizenid,
          o.name,
          json.encode({
               gasoline = 0.0,
               crudeOil = 0.0
          }),
     }
     local res = MySQL.Sync.insert(sqlQuery, QueryData)
     if res ~= 0 then
          -- inject into runtime
          GlobalScirptData:newDevice({
               id = res,
               citizenid = o.citizenid,
               name = o.name,
               metadata = json.encode({
                    gasoline = 0.0,
                    crudeOil = 0.0
               })
          }, 'oilrig_storage')
          return true
     end
     return false
end
-- End Storage

-- CDU
Init_CDU = function(o)
     local sqlQuery = 'INSERT INTO oilrig_cdu (citizenid,metadata) VALUES (?,?)'
     local QueryData = {
          o.citizenid,
          json.encode({
               temp = 0.0,
               req_temp = 0.0,
               state = false,
               oil_storage = 0.0
          }),
     }
     local res = MySQL.Sync.insert(sqlQuery, QueryData)
     if res ~= 0 then
          -- inject into runtime
          GlobalScirptData:newDevice({
               id = res,
               citizenid = o.citizenid,
               metadata = json.encode({
                    temp = 0.0,
                    req_temp = 0.0,
                    state = false,
                    oil_storage = 0.0
               })
          }, 'oilrig_cdu')
          return true
     end
     return false
end

-- End CDU

--------------------
-- DATABASE WRAPPER
--------------------
function InitilaizeAllDataByDatabaseValues_2()
     local oil_well = MySQL.Sync.fetchAll('SELECT * FROM oilrig_position', {})
     local oilrig_storage = MySQL.Sync.fetchAll('SELECT * FROM oilrig_storage', {})
     local oilrig_cdu = MySQL.Sync.fetchAll('SELECT * FROM oilrig_cdu', {})
     local oilrig_blender = MySQL.Sync.fetchAll('SELECT * FROM oilrig_blender', {})
     GlobalScirptData:initPhaseTwo({
          oil_well = oil_well,
          oilrig_storage = oilrig_storage,
          oilrig_cdu = oilrig_cdu,
          oilrig_blender = oilrig_blender
     })
end

function GeneralUpdate_2(options)
     if options.type == nil then
          return
     end
     local sqlQuery = ''
     local QueryData = {}

     if options.type == 'oilrig_storage' or options.type == 'oilrig_cdu' then
          sqlQuery = 'UPDATE ' .. options.type .. ' SET metadata = ? WHERE citizenid = ? AND metadata <> ?'
          QueryData = {
               json.encode(options.metadata),
               options.citizenid,
               json.encode(options.metadata)
          }
     end
     MySQL.Async.execute(sqlQuery, QueryData, function(e)
     end)
end
