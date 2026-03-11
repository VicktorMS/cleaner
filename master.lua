-- master.lua - Coordenador central para limpeza de area
-- Roda em um Computer com Wireless Modem
-- Divide a area em faixas e distribui para as turtles
-- Uso: master x1 y1 z1 x2 y2 z2

---------- ARGUMENTOS ----------
local args = {...}
if #args ~= 6 then
  print("Uso: master x1 y1 z1 x2 y2 z2")
  print("Exemplo: master 100 80 200 132 60 232")
  return
end

local x1 = tonumber(args[1])
local y1 = tonumber(args[2])
local z1 = tonumber(args[3])
local x2 = tonumber(args[4])
local y2 = tonumber(args[5])
local z2 = tonumber(args[6])

if not (x1 and y1 and z1 and x2 and y2 and z2) then
  print("ERRO: Todas as coordenadas devem ser numeros!")
  return
end

---------- CONFIGURACAO ----------
local AREA = {
  x1 = math.min(x1, x2),
  z1 = math.min(z1, z2),
  x2 = math.max(x1, x2),
  z2 = math.max(z1, z2),
  y_top = math.max(y1, y2),
  y_bottom = math.min(y1, y2),
}

-- Largura de cada faixa (cada turtle recebe faixas de STRIP_WIDTH blocos em Z)
local STRIP_WIDTH = 4

local PROTOCOL = "area_clear"
local MODEM_SIDE = "top" -- lado do modem no computador

local TURTLE_TIMEOUT = 120 -- segundos sem resposta antes de redistribuir faixa

---------- ESTADO ----------
local strips = {}       -- faixas de trabalho pendentes
local active = {}       -- {turtle_id = strip}
local last_seen = {}    -- {turtle_id = os.clock()} ultimo contato
local completed = {}    -- faixas concluidas
local turtle_names = {} -- {id = label}

---------- FUNCOES ----------

-- Gera todas as faixas de trabalho
local function generateStrips()
  strips = {}
  local id = 1
  local z = AREA.z1
  while z <= AREA.z2 do
    local z_end = math.min(z + STRIP_WIDTH - 1, AREA.z2)
    table.insert(strips, {
      id = id,
      x1 = AREA.x1,
      x2 = AREA.x2,
      z1 = z,
      z2 = z_end,
      y_top = AREA.y_top,
      y_bottom = AREA.y_bottom,
    })
    id = id + 1
    z = z_end + 1
  end
  print("Total de faixas geradas: " .. #strips)
end

-- Pega a proxima faixa disponivel
local function getNextStrip()
  if #strips > 0 then
    return table.remove(strips, 1)
  end
  return nil
end

-- Mostra status no terminal
local function showStatus()
  term.clear()
  term.setCursorPos(1, 1)
  print("=== COORDENADOR DE LIMPEZA ===")
  print("")
  print("Faixas pendentes: " .. #strips)
  print("Faixas ativas:    " .. #(function() local t={} for k in pairs(active) do t[#t+1]=k end return t end)())
  print("Faixas concluidas: " .. #completed)
  print("")
  print("--- Turtles Ativas ---")
  for id, strip in pairs(active) do
    local name = turtle_names[id] or ("Turtle #" .. id)
    print("  " .. name .. " -> Faixa #" .. strip.id ..
          " (Z:" .. strip.z1 .. "-" .. strip.z2 .. ")")
  end
  print("")
  print("Aguardando mensagens...")
end

-- Verifica turtles que nao respondem e redistribui faixas
local function checkTimeouts()
  local now = os.clock()
  for id, strip in pairs(active) do
    if last_seen[id] and (now - last_seen[id]) > TURTLE_TIMEOUT then
      local name = turtle_names[id] or ("Turtle #" .. id)
      print("[" .. name .. "] TIMEOUT! Faixa #" .. strip.id .. " redistribuida")
      table.insert(strips, 1, strip)
      active[id] = nil
      last_seen[id] = nil
    end
  end
end

-- Processa mensagens das turtles
local function handleMessage(sender_id, msg)
  if type(msg) ~= "table" then return end

  -- Atualiza ultimo contato
  last_seen[sender_id] = os.clock()

  if msg.type == "register" then
    -- Turtle se registrando
    turtle_names[sender_id] = msg.label or ("Turtle #" .. sender_id)
    print("[" .. turtle_names[sender_id] .. "] registrada!")

    -- Envia info da area e primeira faixa
    local strip = getNextStrip()
    if strip then
      active[sender_id] = strip
      rednet.send(sender_id, {
        type = "assignment",
        strip = strip,
        home = msg.home, -- devolve a posicao home da turtle
      }, PROTOCOL)
      print("[" .. turtle_names[sender_id] .. "] recebeu faixa #" .. strip.id)
    else
      rednet.send(sender_id, {type = "wait"}, PROTOCOL)
      print("[" .. turtle_names[sender_id] .. "] sem faixas disponiveis, aguardando")
    end

  elseif msg.type == "done" then
    -- Turtle terminou uma faixa
    local name = turtle_names[sender_id] or ("Turtle #" .. sender_id)
    if active[sender_id] then
      table.insert(completed, active[sender_id])
      print("[" .. name .. "] completou faixa #" .. active[sender_id].id)
      active[sender_id] = nil
    end

    -- Envia proxima faixa
    local strip = getNextStrip()
    if strip then
      active[sender_id] = strip
      rednet.send(sender_id, {
        type = "assignment",
        strip = strip,
      }, PROTOCOL)
      print("[" .. name .. "] recebeu faixa #" .. strip.id)
    else
      rednet.send(sender_id, {type = "finished"}, PROTOCOL)
      print("[" .. name .. "] sem mais trabalho - liberada!")
    end

  elseif msg.type == "status" then
    local name = turtle_names[sender_id] or ("Turtle #" .. sender_id)
    print("[" .. name .. "] " .. (msg.text or "status update"))

  elseif msg.type == "error" then
    local name = turtle_names[sender_id] or ("Turtle #" .. sender_id)
    print("[" .. name .. "] ERRO: " .. (msg.text or "desconhecido"))
    -- Recoloca a faixa na fila
    if active[sender_id] then
      table.insert(strips, 1, active[sender_id])
      active[sender_id] = nil
    end
  end

  showStatus()
end

---------- MAIN ----------
print("Iniciando coordenador...")

-- Abre modem
if peripheral.isPresent(MODEM_SIDE) then
  rednet.open(MODEM_SIDE)
else
  -- Tenta encontrar modem em qualquer lado
  local modem = peripheral.find("modem")
  if modem then
    local side = peripheral.getName(modem)
    rednet.open(side)
  else
    print("ERRO: Modem nao encontrado!")
    return
  end
end

rednet.host(PROTOCOL, "master")
print("Protocolo '" .. PROTOCOL .. "' registrado")

generateStrips()
showStatus()

-- Loop principal
while true do
  local sender, msg = rednet.receive(PROTOCOL, 2)
  if sender then
    handleMessage(sender, msg)
  end

  -- Verifica turtles que nao respondem
  checkTimeouts()

  -- Verifica se tudo foi concluido
  local total_strips_count = 0
  for _ in pairs(active) do total_strips_count = total_strips_count + 1 end

  if #strips == 0 and total_strips_count == 0 and #completed > 0 then
    print("")
    print("=============================")
    print("  LIMPEZA COMPLETA!")
    print("  " .. #completed .. " faixas processadas")
    print("=============================")
    break
  end
end

rednet.unhost(PROTOCOL)
rednet.close()
