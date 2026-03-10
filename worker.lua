-- worker.lua - Programa para Mining Turtles
-- Coloque em cada turtle que vai limpar a area
-- Requer: Mining Turtle + Ender Modem (equipado)
-- Setup: Ender Chest de fuel no SLOT 16 (mesma frequencia do chest na base)
--        Itens minerados sao descartados no chao
-- Uso: worker x y z [north|south|east|west]

---------- ARGUMENTOS ----------
local args = {...}
if #args ~= 4 then
  print("Uso: worker x y z direcao")
  print("Exemplo: worker 100 65 200 north")
  print("Direcoes: north, south, east, west")
  return
end

local start_x = tonumber(args[1])
local start_y = tonumber(args[2])
local start_z = tonumber(args[3])
local start_facing_str = string.lower(args[4])

if not (start_x and start_y and start_z) then
  print("ERRO: Coordenadas devem ser numeros!")
  return
end

local facing_map = {north = 0, east = 1, south = 2, west = 3}
local start_facing = facing_map[start_facing_str]
if not start_facing then
  print("ERRO: Direcao invalida! Use: north, south, east, west")
  return
end

---------- CONFIGURACAO ----------
local PROTOCOL = "area_clear"
local FUEL_RESERVE = 800    -- combustivel minimo antes de reabastecer
local MIN_FREE_SLOTS = 2    -- slots livres minimos antes de descartar
local FUEL_CHEST_SLOT = 16  -- slot do ender chest de combustivel

---------- ESTADO ----------
local pos = {x = 0, y = 0, z = 0}  -- posicao relativa ao home
local facing = start_facing  -- orientacao inicial detectada via argumento
local home_world = {x = start_x, y = start_y, z = start_z}
local working = true

---------- MOVIMENTO COM TRACKING ----------

local function turnLeft()
  turtle.turnLeft()
  facing = (facing - 1) % 4
end

local function turnRight()
  turtle.turnRight()
  facing = (facing + 1) % 4
end

local function face(dir)
  local diff = (dir - facing) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight() turnRight()
  elseif diff == 3 then turnLeft()
  end
end

-- Atualiza posicao apos mover pra frente
local function updatePosForward()
  if facing == 0 then pos.z = pos.z - 1
  elseif facing == 1 then pos.x = pos.x + 1
  elseif facing == 2 then pos.z = pos.z + 1
  elseif facing == 3 then pos.x = pos.x - 1
  end
end

local function forward()
  for attempt = 1, 30 do
    if turtle.forward() then
      updatePosForward()
      return true
    end
    turtle.dig()
    turtle.attack()
    sleep(0.1)
  end
  return false
end

local function up()
  for attempt = 1, 30 do
    if turtle.up() then
      pos.y = pos.y + 1
      return true
    end
    turtle.digUp()
    turtle.attackUp()
    sleep(0.1)
  end
  return false
end

local function down()
  for attempt = 1, 30 do
    if turtle.down() then
      pos.y = pos.y - 1
      return true
    end
    turtle.digDown()
    turtle.attackDown()
    sleep(0.1)
  end
  return false
end

---------- NAVEGACAO ----------

-- Navega para uma posicao relativa ao home
local function goTo(tx, ty, tz)
  -- Sobe primeiro (evita obstaculos)
  while pos.y < ty do
    if not up() then break end
  end

  -- Move em X
  if tx > pos.x then
    face(1) -- leste
  elseif tx < pos.x then
    face(3) -- oeste
  end
  while pos.x ~= tx do
    if not forward() then break end
  end

  -- Move em Z
  if tz > pos.z then
    face(2) -- sul
  elseif tz < pos.z then
    face(0) -- norte
  end
  while pos.z ~= tz do
    if not forward() then break end
  end

  -- Desce por ultimo
  while pos.y > ty do
    if not down() then break end
  end
end

-- Navega para home (sobe primeiro para evitar buracos)
local function goHome()
  -- Sobe para altura segura (pelo menos y=0 ou acima)
  local safe_y = math.max(0, pos.y)
  while pos.y < safe_y do up() end

  -- Vai para X=0, Z=0
  goTo(0, 0, 0)
  face(0) -- virado pra norte (direcao original)
end

-- Forward declarations
local dumpInventory

---------- COMBUSTIVEL ----------

local function needsFuel()
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return false end
  return fuel < FUEL_RESERVE
end

-- Reabastece no local usando Ender Chest do slot 16
local function refuel()
  -- Coloca ender chest embaixo
  turtle.select(FUEL_CHEST_SLOT)
  turtle.digDown() -- limpa bloco embaixo se houver
  if not turtle.placeDown() then
    print("ERRO: Nao conseguiu colocar Ender Chest de fuel!")
    turtle.select(1)
    return
  end

  -- Enche o tanque ao maximo
  local fuel_limit = turtle.getFuelLimit()
  local refueled = false

  for attempt = 1, 100 do
    if turtle.getFuelLevel() >= fuel_limit then
      break
    end

    -- Encontra slot vazio para receber o lava bucket
    local free_slot = nil
    for slot = 1, 15 do
      if turtle.getItemCount(slot) == 0 then
        free_slot = slot
        break
      end
    end

    if not free_slot then
      -- Sem slot livre, descarta itens para liberar espaco
      dumpInventory()
      free_slot = 1
    end

    turtle.select(free_slot)
    if turtle.suckDown(1) then
      turtle.refuel()
      -- Devolve bucket vazio pro ender chest
      local current = turtle.getItemDetail()
      if current and current.name == "minecraft:bucket" then
        turtle.dropDown()
      end
      refueled = true
    else
      if refueled then break end
      print("Sem lava buckets! Aguardando...")
      sleep(10)
    end
  end

  -- Recolhe ender chest de volta pro slot 16
  turtle.select(FUEL_CHEST_SLOT)
  turtle.digDown()
  turtle.select(1)
end

---------- INVENTARIO ----------

local function getFreeSlots()
  local free = 0
  for slot = 1, 15 do -- slot 16 reservado pro ender chest
    if turtle.getItemCount(slot) == 0 then
      free = free + 1
    end
  end
  return free
end

local function needsDump()
  return getFreeSlots() < MIN_FREE_SLOTS
end

-- Descarta todos os itens no chao (exceto slot 16)
dumpInventory = function()
  for slot = 1, 15 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      turtle.drop()
    end
  end
  turtle.select(1)
end

---------- COORDENADAS ----------

-- Converte coordenada absoluta do mundo para relativa ao home
local function worldToLocal(wx, wy, wz)
  if not home_world then return wx, wy, wz end
  return wx - home_world.x, wy - home_world.y, wz - home_world.z
end

---------- LIMPEZA DE AREA ----------

-- Forward declarations
local sendStatus

-- Limpa uma faixa (strip) definida pelo master
local function clearStrip(strip)
  local lx1, ly_top, lz1 = worldToLocal(strip.x1, strip.y_top, strip.z1)
  local lx2, ly_bot, lz2 = worldToLocal(strip.x2, strip.y_bottom, strip.z2)

  -- Garante que x1 <= x2 e z1 <= z2
  if lx1 > lx2 then lx1, lx2 = lx2, lx1 end
  if lz1 > lz2 then lz1, lz2 = lz2, lz1 end

  print("Limpando faixa: X=" .. lx1 .. "-" .. lx2 ..
        " Z=" .. lz1 .. "-" .. lz2 ..
        " Y=" .. ly_top .. "-" .. ly_bot)

  -- Vai para o canto superior da faixa
  goTo(lx1, ly_top, lz1)

  -- Padrão serpentina: percorre X em cada camada Z, desce Y
  local x_dir = 1  -- 1 = crescente, -1 = decrescente
  local z_dir = 1

  local y = ly_top
  while y >= ly_bot do
    -- Percorre o plano XZ nessa altura Y
    local z = (z_dir == 1) and lz1 or lz2
    local z_end = (z_dir == 1) and lz2 or lz1

    while true do
      -- Percorre X nessa linha Z
      local x_start = (x_dir == 1) and lx1 or lx2
      local x_end = (x_dir == 1) and lx2 or lx1

      goTo(x_start, y, z)

      local x = x_start
      while x ~= x_end do
        -- Verifica combustivel e inventario
        if needsFuel() then
          sendStatus("Reabastecendo...")
          refuel()
        end
        if needsDump() then
          sendStatus("Descartando itens...")
          dumpInventory()
        end

        -- Move para proximo X
        x = x + x_dir
        goTo(x, y, z)

        -- Cava acima e abaixo tambem (3 blocos por passada)
        turtle.digUp()
        turtle.digDown()
      end

      -- Inverte direcao X para proxima linha
      x_dir = -x_dir

      -- Proxima linha Z
      if z == z_end then break end
      z = z + z_dir
    end

    -- Inverte direcao Z para proxima camada
    z_dir = -z_dir

    -- Desce para proxima camada (pula 3 se cavou acima/abaixo)
    y = y - 3
    if y >= ly_bot then
      goTo(pos.x, y, pos.z)
    end
  end

  print("Faixa concluida!")
end

---------- COMUNICACAO ----------

local master_id = nil

sendStatus = function(text)
  if master_id then
    rednet.send(master_id, {type = "status", text = text}, PROTOCOL)
  end
  print(text)
end

local function sendError(text)
  if master_id then
    rednet.send(master_id, {type = "error", text = text}, PROTOCOL)
  end
  print("ERRO: " .. text)
end

local function register()
  print("Home: " .. home_world.x .. ", " .. home_world.y .. ", " .. home_world.z)

  -- Procura master
  print("Procurando coordenador...")
  master_id = rednet.lookup(PROTOCOL, "master")

  if not master_id then
    print("Coordenador nao encontrado! Tentando novamente...")
    sleep(3)
    master_id = rednet.lookup(PROTOCOL, "master")
  end

  if not master_id then
    print("ERRO: Coordenador nao encontrado!")
    return false
  end

  print("Coordenador encontrado: #" .. master_id)

  -- Registra com o master
  rednet.send(master_id, {
    type = "register",
    label = os.getComputerLabel() or ("Turtle #" .. os.getComputerID()),
    home = home_world,
    fuel = turtle.getFuelLevel(),
  }, PROTOCOL)

  return true
end

---------- MAIN ----------
print("=== TURTLE WORKER ===")
print("ID: " .. os.getComputerID())
print("Label: " .. (os.getComputerLabel() or "sem nome"))

-- Verifica ender chest no slot 16
local ender_chest = turtle.getItemDetail(FUEL_CHEST_SLOT)
if not ender_chest then
  print("AVISO: Sem Ender Chest no slot " .. FUEL_CHEST_SLOT .. "!")
  print("Coloque um Ender Chest de fuel no slot " .. FUEL_CHEST_SLOT)
  return
end
print("Ender Chest de fuel: OK (slot " .. FUEL_CHEST_SLOT .. ")")

-- Abre modem
local modem = peripheral.find("modem")
if not modem then
  print("ERRO: Modem nao encontrado!")
  print("Equipe um Wireless Modem na turtle")
  return
end
rednet.open(peripheral.getName(modem))

-- Verifica combustivel inicial
local fuel = turtle.getFuelLevel()
if fuel ~= "unlimited" and fuel < 100 then
  print("Combustivel muito baixo (" .. fuel .. ")")
  print("Reabastecendo com Ender Chest...")
  refuel()
end

-- Registra com o master
if not register() then
  return
end

-- Loop principal: recebe faixas e trabalha
while working do
  local sender, msg = rednet.receive(PROTOCOL, 30)

  if not sender then
    -- Timeout - tenta re-registrar
    print("Timeout... re-registrando")
    register()

  elseif sender == master_id and type(msg) == "table" then

    if msg.type == "assignment" then
      local strip = msg.strip
      print("")
      print("Recebeu faixa #" .. strip.id)

      -- Verifica fuel antes de comecar
      if needsFuel() then
        sendStatus("Reabastecendo antes de comecar...")
        refuel()
      end

      -- Limpa a faixa
      local ok, err = pcall(clearStrip, strip)

      if ok then
        -- Reporta conclusao (sem voltar pra home)
        rednet.send(master_id, {
          type = "done",
          strip_id = strip.id,
          fuel = turtle.getFuelLevel(),
        }, PROTOCOL)
      else
        sendError("Falha na faixa #" .. strip.id .. ": " .. tostring(err))
      end

    elseif msg.type == "finished" then
      print("")
      print("=== TRABALHO CONCLUIDO ===")
      print("Sem mais faixas para processar")
      goHome()
      working = false

    elseif msg.type == "wait" then
      print("Sem faixas disponiveis, aguardando...")
      sleep(10)
      rednet.send(master_id, {type = "register",
        label = os.getComputerLabel() or ("Turtle #" .. os.getComputerID()),
        home = home_world,
      }, PROTOCOL)
    end
  end
end

rednet.close()
print("Worker finalizado!")
