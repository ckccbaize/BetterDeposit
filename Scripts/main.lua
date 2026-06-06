print("[BetterDeposit] v0.3.4-betterdeposit starting...")
print("[BetterDeposit] ============================================")
print("[BetterDeposit] Build: 2026-06-05 15:25 | Author: baize")
print("[BetterDeposit] Compatible: UE 5.6 + RogueCore 5.6.1 + UE4SS 3.0.1")
print("[BetterDeposit] Reference: Gen1 _SakuraMods_FastDeposit.pak InitCave Blueprint")
print("[BetterDeposit] ============================================")
print("[BetterDeposit] Multiplayer: TYPE B mod (like MapWideNegotiation)")
print("[BetterDeposit] Each player must install this mod for it to work for them")
print("[BetterDeposit] ============================================")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local Config = {
    bIsEnabled = true,           -- 主开关 (false = 全部 mod 失效)
    TickInterval = 0.5,          -- monitor 检测间隔 (秒)
    ActivitySummaryInterval = 30, -- v0.3.5: 5s 改 30s (baize 15:55 "只保留有用的日志")
    SpeedMultiplier = 10000.0,   -- DepositesPerSecond 倍率 (原版 ~1.0, 10000x)
    AmountMultiplier = 99999.0,  -- DepositeAmount 倍率 (每次 deposit 几乎所有)
    AutoMonitorEnabled = true,   -- 0.5s monitor (log bank 数量变化, 不调游戏函数)
    bDebugMode = true,           -- 详细日志
}

print(string.format("[BetterDeposit] Config: Speed=%g | Amount=%g | TickInterval=%gs | SummaryInterval=%ds",
    Config.SpeedMultiplier, Config.AmountMultiplier, Config.TickInterval, Config.ActivitySummaryInterval))

-- ============================================================================
-- STATE
-- ============================================================================
local State = {
    bIsDepositing = false,
    LastCheckTime = 0,
    AcceleratedBankCount = 0,
    TotalChecks = 0,
    LastKnownBankCount = 0,
    LastSummaryTime = 0,
    SelfTestResults = {},        -- Self-test 6 项结果
}

-- ============================================================================
-- LOG
-- ============================================================================
local function Log(msg)
    if Config.bDebugMode then
        print("[BetterDeposit] " .. msg)
    end
end

-- ============================================================================
-- LAYER 1: SPEED HACK (v0.2.1 验证过)
-- ============================================================================
local FAST_DEPOSIT_SPEED = Config.SpeedMultiplier
local FAST_DEPOSIT_AMOUNT = Config.AmountMultiplier

local function accelerateBank(bank)
    if not bank or not bank:IsValid() then
        return false
    end
    local ok, err = pcall(function()
        local fullName = bank:GetFullName() or "?"
        local oldSpeed = bank.DepositesPerSecond
        local oldAmount = bank.DepositeAmount
        bank.DepositesPerSecond = FAST_DEPOSIT_SPEED
        bank.DepositeAmount = FAST_DEPOSIT_AMOUNT
        local newSpeed = bank.DepositesPerSecond
        local newAmount = bank.DepositeAmount
        Log(string.format("  Accelerated bank: %s | speed: %g -> %g | amount: %g -> %g",
            fullName, oldSpeed, newSpeed, oldAmount, newAmount))
    end)
    if not ok then
        Log(string.format("  accelerateBank FAILED: %s", tostring(err)))
    end
    return ok
end

local function accelerateAllBanks()
    if not Config.bIsEnabled then
        return 0
    end
    local count = 0
    pcall(function()
        local banks = FindAllOf("ResourceBank")
        if banks then
            for _, bank in ipairs(banks) do
                if accelerateBank(bank) then
                    count = count + 1
                end
            end
        end
    end)
    State.AcceleratedBankCount = count
    State.LastKnownBankCount = count
    if count > 0 then
        Log(string.format("Accelerated %d ResourceBank(s) (speed=%g, amount=%g)",
            count, FAST_DEPOSIT_SPEED, FAST_DEPOSIT_AMOUNT))
    end
    return count
end

-- 启动加速
accelerateAllBanks()

-- 2s 定时器 (覆盖新生成的 bank)
ExecuteWithDelay(2000, function()
    accelerateAllBanks()
end)

Log("Speed hack active: deposit will be instant (1s) when player presses E")

-- ============================================================================
-- LAYER 2: MONITOR (找 banks, log 数量变化, 不调游戏函数 - 安全)
-- ============================================================================
local function MonitorBanks()
    if not Config.bIsEnabled or not Config.AutoMonitorEnabled then
        return
    end
    State.TotalChecks = State.TotalChecks + 1
    local count = 0
    pcall(function()
        local banks = FindAllOf("ResourceBank")
        if banks then
            count = #banks
        end
    end)
    if count ~= State.LastKnownBankCount then
        Log(string.format("Bank count changed: %d -> %d (check #%d, likely new donkey spawned)",
            State.LastKnownBankCount, count, State.TotalChecks))
        State.LastKnownBankCount = count
        -- 数量变化时, 立即重新加速 (不等到 2s 定时器)
        accelerateAllBanks()
    end
end

-- 0.5s 定时监控 (UE4SS API 是 ExecuteWithDelay, 不是 Gen1 文档的 CreateTimer)
-- 递归 self-reschedule 模式, 模拟 CreateTimer
local function scheduleMonitor()
    ExecuteWithDelay(math.floor(Config.TickInterval * 1000), function()
        MonitorBanks()
        if Config.bIsEnabled and Config.AutoMonitorEnabled then
            scheduleMonitor()
        end
    end)
end
scheduleMonitor()

-- ============================================================================
-- LAYER 3: CONSOLE COMMANDS (Gen1 风格, 扩展 + SetSpeed)
-- ============================================================================

_G.BetterDeposit_Toggle = function()
    Config.bIsEnabled = not Config.bIsEnabled
    Log("Toggled: bIsEnabled = " .. tostring(Config.bIsEnabled))
    if Config.bIsEnabled then
        accelerateAllBanks()  -- 重新启用时立即扫一次
    end
end

_G.BetterDeposit_Status = function()
    Log("=== Status ===")
    Log("  bIsEnabled          = " .. tostring(Config.bIsEnabled))
    Log("  AutoMonitorEnabled  = " .. tostring(Config.AutoMonitorEnabled))
    Log("  TickInterval        = " .. Config.TickInterval .. "s")
    Log("  ActivitySummaryInterval = " .. Config.ActivitySummaryInterval .. "s")
    Log("  SpeedMultiplier     = " .. Config.SpeedMultiplier)
    Log("  AmountMultiplier    = " .. Config.AmountMultiplier)
    Log("  AcceleratedBankCount = " .. State.AcceleratedBankCount)
    Log("  TotalChecks         = " .. State.TotalChecks)
    Log("  LastKnownBankCount  = " .. State.LastKnownBankCount)
    Log("  bIsDepositing       = " .. tostring(State.bIsDepositing))
end

_G.BetterDeposit_SetInterval = function(interval)
    if interval and tonumber(interval) and tonumber(interval) > 0 then
        Config.TickInterval = tonumber(interval)
        Log("TickInterval set to: " .. Config.TickInterval .. "s (restart mod to apply)")
    else
        Log("Invalid interval. Usage: BetterDeposit_SetInterval(0.5)")
    end
end

_G.BetterDeposit_SetSpeed = function(speed)
    if speed and tonumber(speed) and tonumber(speed) > 0 then
        Config.SpeedMultiplier = tonumber(speed)
        FAST_DEPOSIT_SPEED = Config.SpeedMultiplier
        Log("SpeedMultiplier set to: " .. FAST_DEPOSIT_SPEED)
        accelerateAllBanks()  -- 立即应用
    else
        Log("Invalid speed. Usage: BetterDeposit_SetSpeed(10000.0)")
    end
end

-- ============================================================================
-- LAYER 5: SELF-TEST 6 项 (启动跑一次)
-- ============================================================================
Log("--- Self-test starting ---")

local function selfTestItem(name, fn)
    local ok, err = pcall(fn)
    if ok then
        Log(string.format("  Self-test %d/6: %s = OK", #State.SelfTestResults + 1, name))
        table.insert(State.SelfTestResults, { name = name, ok = true })
    else
        Log(string.format("  Self-test %d/6: %s = FAILED (%s)", #State.SelfTestResults + 1, name, tostring(err)))
        table.insert(State.SelfTestResults, { name = name, ok = false, err = tostring(err) })
    end
end

-- v0.3.4 修复: 空间站没 donkey 时 FindAllOf 返回 nil 是预期, 不应 error
selfTestItem("FindAllOf(\"ResourceBank\")", function()
    local banks = FindAllOf("ResourceBank")
    -- 允许 nil (空间站) 或非空数组 (副本)
    if banks ~= nil and type(banks) ~= "table" then
        error("returned non-table type: " .. type(banks))
    end
end)

selfTestItem("bank:IsValid()", function()
    local banks = FindAllOf("ResourceBank")
    if banks and #banks > 0 then
        if not banks[1]:IsValid() then error("bank not valid") end
    end
    -- 没 banks 时 (空间站) 跳过
end)

selfTestItem("bank.DepositesPerSecond set", function()
    local banks = FindAllOf("ResourceBank")
    if banks and #banks > 0 then
        local b = banks[1]
        local old = b.DepositesPerSecond
        b.DepositesPerSecond = 10000.0
        if b.DepositesPerSecond ~= 10000.0 then error("set failed") end
        b.DepositesPerSecond = old  -- restore
    end
    -- 没 banks 时跳过
end)

selfTestItem("0.5s monitor schedule", function()
    if not Config.AutoMonitorEnabled then error("monitor disabled") end
    if Config.TickInterval ~= 0.5 then error("interval != 0.5") end
end)

selfTestItem("_G commands registered", function()
    if not _G.BetterDeposit_Toggle then error("Toggle not registered") end
    if not _G.BetterDeposit_Status then error("Status not registered") end
    if not _G.BetterDeposit_SetInterval then error("SetInterval not registered") end
    if not _G.BetterDeposit_SetSpeed then error("SetSpeed not registered") end
end)

selfTestItem("ExecuteWithDelay(2000, ...)", function()
    ExecuteWithDelay(2000, function() end)  -- 2s 后空函数, 验证 API 不报错
end)

local passedCount = 0
for _, r in ipairs(State.SelfTestResults) do
    if r.ok then passedCount = passedCount + 1 end
end
if passedCount == #State.SelfTestResults then
    Log(string.format("--- Self-test PASSED (%d/%d) - ready for cave ---", passedCount, #State.SelfTestResults))
else
    Log(string.format("--- Self-test FAILED (%d/%d) - investigate ---", passedCount, #State.SelfTestResults))
end

-- ============================================================================
-- LAYER 6: ACTIVITY SUMMARY (5s 一次)
-- ============================================================================
local function activitySummary()
    if not Config.bIsEnabled then
        return
    end
    local now = os.time()
    if State.LastSummaryTime == 0 then
        State.LastSummaryTime = now
        return  -- 第一次不打印, 等 5s 后
    end
    if now - State.LastSummaryTime >= Config.ActivitySummaryInterval then
        Log(string.format("Activity: checks=%d | banks=%d | accelerated=%d | uptime=%ds",
            State.TotalChecks, State.LastKnownBankCount, State.AcceleratedBankCount,
            now - State.LastSummaryTime))
        State.LastSummaryTime = now
    end
end

-- Activity summary 也走 scheduleActivitySummary 递归 (每 30s 一次, v0.3.5 改)
local function scheduleActivitySummary()
    ExecuteWithDelay(Config.ActivitySummaryInterval * 1000, function()
        activitySummary()
        scheduleActivitySummary()
    end)
end
scheduleActivitySummary()

print("[BetterDeposit] ============================================")
print("[BetterDeposit] v0.3.4-betterdeposit loaded! Commands:")
print("  BetterDeposit_Toggle()        - Enable/disable mod")
print("  BetterDeposit_Status()        - Show status")
print("  BetterDeposit_SetInterval(s)  - Set monitor interval (restart to apply)")
print("  BetterDeposit_SetSpeed(s)     - Set deposit speed multiplier (immediate apply)")
print("[BetterDeposit] Setup complete - deposit will be instant (1s) when player presses E")
print("[BetterDeposit] ============================================")
