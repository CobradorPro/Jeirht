--[[
	PORTAL QUÂNTICO GIGANTE - LocalScript (PC e Mobile)
	-------------------------------------------------
	• Anel metálico gigante (30 m de diâmetro por padrão) inspirado em um
	  "stargate": 8 travas maciças, treliça interna, anel interno com furos,
	  painéis em relevo, rebites, base com degraus e pilares de apoio.
	• Tool na Backpack (RequiresHandle = false), recriada ao renascer.
	• Holograma leve segue a mira (mouse no PC / centro da tela no celular).
	• Ao ativar: as peças caem em levas, faíscas, onda de choque, tremor,
	  vórtice de energia animado e teletransporte com flash.
	Coloque em StarterPlayerScripts.
]]

---------------------------------------------------------------------
-- CONFIGURAÇÕES
---------------------------------------------------------------------
local CONFIG = {
	NOME_TOOL          = "Portal Quântico",
	DIAMETRO_METROS    = 30,                            -- tamanho do portal
	STUDS_POR_METRO    = 1 / 0.28,                      -- 1 stud = 0,28 m
	COR_ENERGIA        = Color3.fromRGB(0, 200, 255),   -- neon / energia
	COR_METAL          = Color3.fromRGB(115, 115, 120), -- metal principal
	COR_METAL_ESCURO   = Color3.fromRGB(55, 55, 60),    -- sulcos / furos
	COR_DETALHE        = Color3.fromRGB(160, 160, 165), -- painéis em relevo
	SEGMENTOS          = 48,      -- resolução dos anéis
	REBITES            = true,    -- desligue para menos peças
	ALCANCE_MIRA       = 800,
	PECAS_POR_LEVA     = 14,      -- quantas peças caem juntas
	TEMPO_ENTRE_LEVAS  = 0.04,
	ALTURA_QUEDA       = 140,
	DURACAO_QUEDA      = 0.7,
	TRANSP_HOLOGRAMA   = 0.6,
	TEMPO_PORTAL_ATIVO = 20,
	FORCA_TREMOR       = 1.6,
	DURACAO_TREMOR     = 1.2,
}

---------------------------------------------------------------------
-- SERVIÇOS
---------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local jogador = Players.LocalPlayer
local camera  = workspace.CurrentCamera

---------------------------------------------------------------------
-- LIMPEZA
---------------------------------------------------------------------
if _G.PortalQuantico_Cleanup then
	pcall(_G.PortalQuantico_Cleanup)
end

local conexoes = {}
local instancias = {}

local function rastrear(inst)
	table.insert(instancias, inst)
	return inst
end

local pastaEfeitos = rastrear(Instance.new("Folder"))
pastaEfeitos.Name = "PortalQuantico_Efeitos"
pastaEfeitos.Parent = workspace

local pastaHolograma = rastrear(Instance.new("Folder"))
pastaHolograma.Name = "PortalQuantico_Holograma"
pastaHolograma.Parent = workspace

local guiFlash = rastrear(Instance.new("ScreenGui"))
guiFlash.Name = "PortalQuantico_Flash"
guiFlash.IgnoreGuiInset = true
guiFlash.ResetOnSpawn = false
guiFlash.Parent = jogador:WaitForChild("PlayerGui")

local frameFlash = Instance.new("Frame")
frameFlash.Size = UDim2.fromScale(1, 1)
frameFlash.BackgroundColor3 = Color3.new(1, 1, 1)
frameFlash.BackgroundTransparency = 1
frameFlash.BorderSizePixel = 0
frameFlash.Parent = guiFlash

local toolAtual = nil
local construindo = false
local conexaoHolo = nil

_G.PortalQuantico_Cleanup = function()
	if conexaoHolo then conexaoHolo:Disconnect() conexaoHolo = nil end
	for _, c in ipairs(conexoes) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(conexoes)
	if toolAtual then pcall(function() toolAtual:Destroy() end) end
	for _, inst in ipairs(instancias) do
		pcall(function() inst:Destroy() end)
	end
	table.clear(instancias)
	local char = jogador.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.CameraOffset = Vector3.zero end
	_G.PortalQuantico_Cleanup = nil
end

---------------------------------------------------------------------
-- GEOMETRIA DO PORTAL
---------------------------------------------------------------------
local RAD90 = math.rad(90)
local BLOCO = Enum.PartType.Block
local CILINDRO = Enum.PartType.Cylinder

-- Retorna lista de peças, altura do centro, escala S, raio da energia
local function obterPecas()
	local pecas = {}
	local diametro = CONFIG.DIAMETRO_METROS * CONFIG.STUDS_POR_METRO
	local Rext = diametro / 2
	local S = Rext / 50                 -- unidade de escala
	local Ro = Rext - 4 * S             -- anel externo (linha central)
	local Ri = Ro - 13 * S              -- anel interno (linha central)
	local rA = Ri + 2 * S               -- início da treliça
	local rB = Ro - 4 * S               -- fim da treliça
	local Ren = Ri - 2.7 * S            -- raio da energia
	local cy = Rext + 6 * S             -- altura do centro
	local N = CONFIG.SEGMENTOS
	local passo = (math.pi * 2) / N
	local centro = CFrame.new(0, cy, 0)

	local function add(t)
		t.transp = t.transp or 0
		table.insert(pecas, t)
	end

	-- CFrame de um segmento do anel: X = radial, Y = tangencial, Z = profundidade
	local function seg(raio, a, z)
		return centro * CFrame.new(math.cos(a) * raio, math.sin(a) * raio, z) * CFrame.Angles(0, 0, a)
	end

	local function comp(raio, frac)
		return (2 * math.pi * raio / N) * (frac or 1.06)
	end

	-- Barra entre dois pontos no plano XY (local ao centro)
	local function barra(x1, y1, x2, y2, z, esp)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local phi = math.atan2(dy, dx)
		return centro * CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, z) * CFrame.Angles(0, 0, phi - RAD90),
			Vector3.new(esp, len, esp)
	end

	---------------- BASE ----------------
	add({ nome = "Plataforma", forma = BLOCO, material = Enum.Material.Concrete,
		cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(Rext * 1.5, 4 * S, 26 * S),
		offset = CFrame.new(0, 2 * S, 0), holo = true })
	add({ nome = "PlataformaBorda", forma = BLOCO, material = Enum.Material.Metal,
		cor = CONFIG.COR_DETALHE, tamanho = Vector3.new(Rext * 1.52, 0.6 * S, 26.4 * S),
		offset = CFrame.new(0, 4 * S, 0) })
	for _, lado in ipairs({ -1, 1 }) do
		for i = 1, 3 do
			local h = 4 * S * (1 - i * 0.25)
			add({ nome = "Degrau", forma = BLOCO, material = Enum.Material.Concrete,
				cor = CONFIG.COR_METAL, tamanho = Vector3.new(Rext * 0.6, h, 3 * S),
				offset = CFrame.new(0, h / 2, lado * (13 * S + i * 3 * S - 1.5 * S)) })
		end
		-- Faixa neon na borda da plataforma
		add({ nome = "FaixaNeon", forma = BLOCO, material = Enum.Material.Neon,
			cor = CONFIG.COR_ENERGIA, tamanho = Vector3.new(Rext * 1.4, 0.4 * S, 0.4 * S),
			offset = CFrame.new(0, 3.2 * S, lado * 13.1 * S), neon = true })
	end
	-- Pilares de apoio sob o anel
	for _, lado in ipairs({ -1, 1 }) do
		local a = -math.pi / 2 + lado * math.rad(28)
		local yAnel = cy + math.sin(a) * Rext
		local x = math.cos(a) * Rext * 0.95
		local h = yAnel + 2 * S - 4 * S
		add({ nome = "Apoio", forma = BLOCO, material = Enum.Material.Metal,
			cor = CONFIG.COR_METAL, tamanho = Vector3.new(10 * S, h, 12 * S),
			offset = CFrame.new(x, 4 * S + h / 2, 0), holo = true })
		for _, zs in ipairs({ -1, 1 }) do
			add({ nome = "ApoioPlaca", forma = BLOCO, material = Enum.Material.Metal,
				cor = CONFIG.COR_DETALHE, tamanho = Vector3.new(8 * S, h * 0.8, 0.6 * S),
				offset = CFrame.new(x, 4 * S + h / 2, zs * 6.2 * S) })
			add({ nome = "ApoioNeon", forma = BLOCO, material = Enum.Material.Neon,
				cor = CONFIG.COR_ENERGIA, tamanho = Vector3.new(0.6 * S, h * 0.6, 0.3 * S),
				offset = CFrame.new(x, 4 * S + h / 2, zs * 6.6 * S), neon = true })
		end
	end

	---------------- ANEL EXTERNO ----------------
	for i = 0, N - 1 do
		local a = i * passo
		add({ nome = "AnelExterno", forma = BLOCO, material = Enum.Material.Metal,
			cor = CONFIG.COR_METAL, tamanho = Vector3.new(8 * S, comp(Ro), 7 * S),
			offset = seg(Ro, a, 0), holo = true })
	end
	-- Painéis em relevo (com fendas entre eles)
	for _, zs in ipairs({ -1, 1 }) do
		for i = 0, N - 1 do
			local a = i * passo
			add({ nome = "Painel", forma = BLOCO, material = Enum.Material.Slate,
				cor = CONFIG.COR_DETALHE, tamanho = Vector3.new(6 * S, comp(Ro, 0.86), 0.6 * S),
				offset = seg(Ro, a, zs * 3.8 * S) })
		end
	end
	-- Rebites
	if CONFIG.REBITES then
		for _, zs in ipairs({ -1, 1 }) do
			for i = 0, N - 1 do
				local a = i * passo
				for _, dr in ipairs({ -2.4, 2.4 }) do
					add({ nome = "Rebite", forma = CILINDRO, material = Enum.Material.Metal,
						cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(0.5 * S, 1 * S, 1 * S),
						offset = seg(Ro + dr * S, a, zs * 4.2 * S) * CFrame.Angles(0, RAD90, 0) })
				end
			end
		end
	end

	---------------- TRELIÇA ----------------
	for _, zs in ipairs({ -1, 1 }) do
		local z = zs * 2.2 * S
		for i = 0, N - 1 do
			local a = i * passo
			local b = a + passo
			-- Montante radial
			add({ nome = "TrelicaRadial", forma = BLOCO, material = Enum.Material.Metal,
				cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(rB - rA, 0.7 * S, 0.7 * S),
				offset = seg((rA + rB) / 2, a, z) })
			-- Diagonal alternada (forma o "X")
			local r1, r2 = rA, rB
			if i % 2 == 1 then r1, r2 = rB, rA end
			local cf, tam = barra(math.cos(a) * r1, math.sin(a) * r1,
				math.cos(b) * r2, math.sin(b) * r2, z, 0.5 * S)
			add({ nome = "TrelicaDiagonal", forma = BLOCO, material = Enum.Material.Metal,
				cor = CONFIG.COR_METAL, tamanho = tam, offset = cf })
			-- Anel de amarração no meio da treliça
			add({ nome = "TrelicaAmarra", forma = BLOCO, material = Enum.Material.Metal,
				cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(0.5 * S, comp((rA + rB) / 2), 0.5 * S),
				offset = seg((rA + rB) / 2, a, z) })
		end
	end

	---------------- ANEL INTERNO ----------------
	for i = 0, N - 1 do
		local a = i * passo
		add({ nome = "AnelInterno", forma = BLOCO, material = Enum.Material.Metal,
			cor = CONFIG.COR_METAL, tamanho = Vector3.new(4 * S, comp(Ri), 5 * S),
			offset = seg(Ri, a, 0), holo = true })
		add({ nome = "Borda", forma = BLOCO, material = Enum.Material.Metal,
			cor = CONFIG.COR_DETALHE, tamanho = Vector3.new(0.8 * S, comp(Ri - 2.3 * S), 6.5 * S),
			offset = seg(Ri - 2.3 * S, a, 0) })
	end
	-- Furos do anel interno
	for _, zs in ipairs({ -1, 1 }) do
		for i = 0, N - 1 do
			local a = i * passo + passo / 2
			add({ nome = "Furo", forma = CILINDRO, material = Enum.Material.Metal,
				cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(0.4 * S, 1.2 * S, 1.2 * S),
				offset = seg(Ri, a, zs * 2.6 * S) * CFrame.Angles(0, RAD90, 0) })
		end
	end

	---------------- 8 TRAVAS ----------------
	for k = 0, 7 do
		local a = k * math.pi / 4
		local rc = Ro + 1 * S
		add({ nome = "Trava", forma = BLOCO, material = Enum.Material.Metal,
			cor = CONFIG.COR_METAL, tamanho = Vector3.new(10 * S, 9 * S, 10 * S),
			offset = seg(rc, a, 0), holo = true })
		add({ nome = "TravaOrelha", forma = BLOCO, material = Enum.Material.Metal,
			cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(3 * S, 6 * S, 7 * S),
			offset = seg(Ro + 7 * S, a, 0) })
		add({ nome = "TravaLuz", forma = BLOCO, material = Enum.Material.Neon,
			cor = CONFIG.COR_ENERGIA, tamanho = Vector3.new(1 * S, 3 * S, 6 * S),
			offset = seg(Ro - 4.5 * S, a, 0), neon = true })
		for _, zs in ipairs({ -1, 1 }) do
			add({ nome = "TravaPlaca", forma = BLOCO, material = Enum.Material.Slate,
				cor = CONFIG.COR_DETALHE, tamanho = Vector3.new(8 * S, 7 * S, 0.8 * S),
				offset = seg(rc, a, zs * 5.4 * S) })
			for _, dr in ipairs({ -2.2, 2.2 }) do
				add({ nome = "TravaSulco", forma = BLOCO, material = Enum.Material.Metal,
					cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(0.8 * S, 5.5 * S, 0.4 * S),
					offset = seg(rc + dr * S, a, zs * 5.9 * S) })
			end
			add({ nome = "TravaSulcoCentral", forma = BLOCO, material = Enum.Material.Metal,
				cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(5 * S, 0.8 * S, 0.4 * S),
				offset = seg(rc, a, zs * 5.9 * S) })
			for _, dr in ipairs({ -3, 3 }) do
				for _, dt in ipairs({ -2.8, 2.8 }) do
					add({ nome = "TravaParafuso", forma = CILINDRO, material = Enum.Material.Metal,
						cor = CONFIG.COR_METAL_ESCURO, tamanho = Vector3.new(0.6 * S, 1 * S, 1 * S),
						offset = seg(rc, a, 0) * CFrame.new(dr * S, dt * S, zs * 6 * S) * CFrame.Angles(0, RAD90, 0) })
				end
			end
		end
	end

	---------------- ENERGIA ----------------
	local discos = { { 1, 0.35 }, { 0.75, 0.4 }, { 0.5, 0.3 }, { 0.28, 0.15 } }
	for i, d in ipairs(discos) do
		local D = 2 * Ren * d[1]
		add({ nome = "Energia", forma = CILINDRO, material = Enum.Material.Neon,
			cor = CONFIG.COR_ENERGIA:Lerp(Color3.new(1, 1, 1), (i - 1) * 0.2),
			tamanho = Vector3.new(0.3, D, D),
			offset = CFrame.new(0, cy, -(i - 1) * 0.15 * S) * CFrame.Angles(0, RAD90, 0),
			transp = d[2], tipo = "energia" })
	end
	for k = 0, 5 do
		local localCf = CFrame.Angles(0, 0, k * math.pi / 3)
			* CFrame.new(Ren * 0.5, 0, -0.8 * S) * CFrame.Angles(0, 0, math.rad(25))
		add({ nome = "Vortice", forma = BLOCO, material = Enum.Material.Neon,
			cor = Color3.new(1, 1, 1):Lerp(CONFIG.COR_ENERGIA, 0.4),
			tamanho = Vector3.new(Ren * 0.9, 0.6 * S, 0.2 * S),
			offset = centro * localCf, localCf = localCf, transp = 0.3, tipo = "vortice" })
	end

	return pecas, cy, S, Ren
end

local function criarParte(spec, parent)
	local p = Instance.new("Part")
	p.Name = spec.nome
	p.Shape = spec.forma
	p.Material = spec.material
	p.Color = spec.cor
	p.Size = spec.tamanho
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

---------------------------------------------------------------------
-- MIRA
---------------------------------------------------------------------
local function usandoToque()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function obterAlvo()
	local pontoTela
	if usandoToque() then
		pontoTela = camera.ViewportSize / 2
	else
		pontoTela = UserInputService:GetMouseLocation()
	end
	local raio = camera:ViewportPointToRay(pontoTela.X, pontoTela.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filtro = { pastaHolograma, pastaEfeitos }
	if jogador.Character then table.insert(filtro, jogador.Character) end
	params.FilterDescendantsInstances = filtro

	local resultado = workspace:Raycast(raio.Origin, raio.Direction * CONFIG.ALCANCE_MIRA, params)
	if resultado then
		return resultado.Position
	end
	return nil
end

local function cframeBase(posicao)
	local char = jogador.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origem = hrp and hrp.Position or camera.CFrame.Position
	local dir = Vector3.new(origem.X - posicao.X, 0, origem.Z - posicao.Z)
	if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, 1) end
	return CFrame.lookAt(posicao, posicao + dir.Unit)
end

---------------------------------------------------------------------
-- HOLOGRAMA (versão leve: só peças principais)
---------------------------------------------------------------------
local holoPartes = {}
local holoOffsets = {}

local function destruirHolograma()
	if conexaoHolo then conexaoHolo:Disconnect() conexaoHolo = nil end
	pastaHolograma:ClearAllChildren()
	table.clear(holoPartes)
	table.clear(holoOffsets)
end

local function criarHolograma()
	destruirHolograma()
	local pecas, cy, S, Ren = obterPecas()
	for _, spec in ipairs(pecas) do
		if spec.holo or spec.tipo == "energia" then
			local p = criarParte(spec, pastaHolograma)
			p.Material = Enum.Material.Neon
			p.Color = CONFIG.COR_ENERGIA
			p.Transparency = 1
			table.insert(holoPartes, p)
			table.insert(holoOffsets, spec.offset)
		end
	end
	local scan = Instance.new("Part")
	scan.Name = "Scan"
	scan.Anchored = true
	scan.CanCollide = false
	scan.CanQuery = false
	scan.CanTouch = false
	scan.Material = Enum.Material.Neon
	scan.Color = Color3.new(1, 1, 1)
	scan.Size = Vector3.new(cy * 2.1, 0.4 * S, 0.6 * S)
	scan.Transparency = 1
	scan.Parent = pastaHolograma

	local cframes = table.create(#holoPartes)
	local inicio = os.clock()
	conexaoHolo = RunService.RenderStepped:Connect(function()
		local alvo = obterAlvo()
		local t = os.clock() - inicio
		if alvo then
			local base = cframeBase(alvo)
			for i, off in ipairs(holoOffsets) do
				cframes[i] = base * off
			end
			workspace:BulkMoveTo(holoPartes, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			local tr = math.clamp(CONFIG.TRANSP_HOLOGRAMA + math.sin(t * 5) * 0.15, 0, 1)
			for _, p in ipairs(holoPartes) do
				if p.Name == "Energia" then
					p.Transparency = math.min(tr + 0.3, 0.95)
				else
					p.Transparency = tr
				end
			end
			local yScan = cy + math.sin(t * 2) * cy
			scan.CFrame = base * CFrame.new(0, math.max(yScan, 1), 0)
			scan.Transparency = 0.2
		else
			for _, p in ipairs(holoPartes) do p.Transparency = 1 end
			scan.Transparency = 1
		end
	end)
end

---------------------------------------------------------------------
-- EFEITOS
---------------------------------------------------------------------
local function emitirFaiscas(posicao, quantidade, escala)
	escala = escala or 1
	local ancora = Instance.new("Part")
	ancora.Anchored = true
	ancora.CanCollide = false
	ancora.CanQuery = false
	ancora.Transparency = 1
	ancora.Size = Vector3.new(0.2, 0.2, 0.2)
	ancora.Position = posicao
	ancora.Parent = pastaEfeitos

	local emissor = Instance.new("ParticleEmitter")
	emissor.Color = ColorSequence.new(Color3.new(1, 1, 1), CONFIG.COR_ENERGIA)
	emissor.LightEmission = 1
	emissor.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 * escala),
		NumberSequenceKeypoint.new(1, 0),
	})
	emissor.Lifetime = NumberRange.new(0.4, 0.9)
	emissor.Speed = NumberRange.new(15 * escala, 40 * escala)
	emissor.SpreadAngle = Vector2.new(180, 180)
	emissor.Acceleration = Vector3.new(0, -50, 0)
	emissor.Drag = 2
	emissor.Rate = 0
	emissor.Parent = ancora
	emissor:Emit(quantidade)

	task.delay(1.5, function() ancora:Destroy() end)
end

local function ondaDeChoque(cfBase, raio)
	local onda = Instance.new("Part")
	onda.Shape = Enum.PartType.Cylinder
	onda.Material = Enum.Material.Neon
	onda.Color = CONFIG.COR_ENERGIA
	onda.Anchored = true
	onda.CanCollide = false
	onda.CanQuery = false
	onda.Size = Vector3.new(0.5, 4, 4)
	onda.CFrame = cfBase * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, RAD90)
	onda.Transparency = 0.1
	onda.Parent = pastaEfeitos

	local tw = TweenService:Create(onda,
		TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.5, raio * 5, raio * 5), Transparency = 1 })
	tw:Play()
	tw.Completed:Connect(function() onda:Destroy() end)
end

local function tremerCamera(duracao, forca)
	local char = jogador.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local inicio = os.clock()
	local con
	con = RunService.RenderStepped:Connect(function()
		local passado = os.clock() - inicio
		if passado >= duracao or not hum.Parent then
			con:Disconnect()
			hum.CameraOffset = Vector3.zero
			return
		end
		local f = forca * (1 - passado / duracao)
		hum.CameraOffset = Vector3.new(
			(math.random() - 0.5) * 2 * f,
			(math.random() - 0.5) * 2 * f,
			(math.random() - 0.5) * 2 * f)
	end)
	table.insert(conexoes, con)
end

local function pulsoDeLuz(posicao, alcance)
	local ancora = Instance.new("Part")
	ancora.Anchored = true
	ancora.CanCollide = false
	ancora.CanQuery = false
	ancora.Transparency = 1
	ancora.Size = Vector3.new(0.2, 0.2, 0.2)
	ancora.Position = posicao
	ancora.Parent = pastaEfeitos

	local luz = Instance.new("PointLight")
	luz.Color = CONFIG.COR_ENERGIA
	luz.Brightness = 0
	luz.Range = math.min(alcance, 60)
	luz.Parent = ancora

	local subir = TweenService:Create(luz, TweenInfo.new(0.15), { Brightness = 15 })
	local descer = TweenService:Create(luz, TweenInfo.new(1.4, Enum.EasingStyle.Quad), { Brightness = 0 })
	subir:Play()
	subir.Completed:Connect(function() descer:Play() end)
	descer.Completed:Connect(function() ancora:Destroy() end)
end

local function flashTela()
	frameFlash.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(CONFIG.COR_ENERGIA, 0.3)
	frameFlash.BackgroundTransparency = 0
	TweenService:Create(frameFlash,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
end

---------------------------------------------------------------------
-- CONSTRUÇÃO + TELETRANSPORTE
---------------------------------------------------------------------
local function construirPortal(posicao)
	construindo = true
	local base = cframeBase(posicao)
	local pecas, cy, S, Ren = obterPecas()
	local modelo = Instance.new("Model")
	modelo.Name = "PortalGigante"
	modelo.Parent = pastaEfeitos

	local partes = {}
	local energias = {}
	local vortices, vorticeCf = {}, {}
	local neons = {}

	for i, spec in ipairs(pecas) do
		local p = criarParte(spec, modelo)
		local destino = base * spec.offset
		p.CFrame = destino + Vector3.new(0, CONFIG.ALTURA_QUEDA, 0)
		p.Transparency = 1
		table.insert(partes, p)

		if spec.tipo == "energia" then
			table.insert(energias, { parte = p, transp = spec.transp })
		elseif spec.tipo == "vortice" then
			table.insert(vortices, p)
			table.insert(vorticeCf, spec.localCf)
		elseif spec.neon then
			table.insert(neons, p)
		end

		TweenService:Create(p,
			TweenInfo.new(CONFIG.DURACAO_QUEDA, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = destino, Transparency = spec.transp }):Play()

		if i % CONFIG.PECAS_POR_LEVA == 1 then
			task.delay(CONFIG.DURACAO_QUEDA * 0.6, function()
				emitirFaiscas(destino.Position, 12, math.max(S, 1))
			end)
		end
		if i % CONFIG.PECAS_POR_LEVA == 0 then
			task.wait(CONFIG.TEMPO_ENTRE_LEVAS)
		end
	end

	task.wait(CONFIG.DURACAO_QUEDA)

	-- Final épico
	local cfCentro = base * CFrame.new(0, cy, 0)
	ondaDeChoque(base, cy)
	tremerCamera(CONFIG.DURACAO_TREMOR, CONFIG.FORCA_TREMOR)
	pulsoDeLuz(cfCentro.Position, cy)
	emitirFaiscas(cfCentro.Position, 120, math.max(S * 2, 1))

	-- Animação contínua da energia e vórtice
	local inicio = os.clock()
	local cframesV = table.create(#vortices)
	local conAnim = RunService.Heartbeat:Connect(function()
		local t = os.clock() - inicio
		for i, e in ipairs(energias) do
			if e.parte.Parent then
				e.parte.Transparency = math.clamp(e.transp + math.sin(t * 3 + i) * 0.12, 0, 1)
			end
		end
		for i, lc in ipairs(vorticeCf) do
			cframesV[i] = cfCentro * CFrame.Angles(0, 0, t * 1.6) * lc
		end
		if #vortices > 0 and vortices[1].Parent then
			workspace:BulkMoveTo(vortices, cframesV, Enum.BulkMoveMode.FireCFrameChanged)
		end
		local brilho = 0.5 + math.sin(t * 4) * 0.5
		for _, n in ipairs(neons) do
			n.Color = CONFIG.COR_ENERGIA:Lerp(Color3.new(1, 1, 1), brilho * 0.4)
		end
	end)
	table.insert(conexoes, conAnim)

	task.wait(0.4)

	-- Teletransporte: atravessa o portal até o outro lado da plataforma
	local char = jogador.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		flashTela()
		local destino = base * CFrame.new(0, 4 * S + 3.5, 10 * S)
		char:PivotTo(CFrame.lookAt(destino.Position, destino.Position - base.LookVector))
		emitirFaiscas(destino.Position, 50, 1)
	end

	construindo = false

	-- Desmontagem
	task.delay(CONFIG.TEMPO_PORTAL_ATIVO, function()
		for i = #partes, 1, -1 do
			local p = partes[i]
			if p.Parent then
				TweenService:Create(p,
					TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In),
					{ Transparency = 1, CFrame = p.CFrame + Vector3.new(0, 20, 0) }):Play()
			end
			if i % CONFIG.PECAS_POR_LEVA == 0 then task.wait(0.02) end
		end
		task.wait(0.7)
		conAnim:Disconnect()
		if modelo.Parent then modelo:Destroy() end
	end)
end

---------------------------------------------------------------------
-- TOOL
---------------------------------------------------------------------
local function criarTool()
	if toolAtual then pcall(function() toolAtual:Destroy() end) end
	local mochila = jogador:WaitForChild("Backpack")

	local tool = Instance.new("Tool")
	tool.Name = CONFIG.NOME_TOOL
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Toque/clique para erguer o portal gigante"
	tool.Parent = mochila
	toolAtual = tool

	tool.Equipped:Connect(function()
		criarHolograma()
	end)

	tool.Unequipped:Connect(function()
		destruirHolograma()
	end)

	tool.Activated:Connect(function()
		if construindo then return end
		local alvo = obterAlvo()
		if not alvo then return end
		task.spawn(construirPortal, alvo)
	end)

	tool.Destroying:Connect(function()
		destruirHolograma()
	end)
end

table.insert(conexoes, jogador.CharacterAdded:Connect(function(char)
	construindo = false
	char:WaitForChild("Humanoid")
	task.wait(0.1)
	criarTool()
end))

if jogador.Character then
	criarTool()
end
