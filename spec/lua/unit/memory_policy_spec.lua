describe("adaptive memory policy", function()
    local original_util
    local original_render_cache
    local original_decode_cache
    local original_db_bookinfo

    before_each(function()
        original_util = package.loaded.util
        original_render_cache = package.loaded["common/cover_render_cache"]
        original_decode_cache = package.loaded["common/cover_decode_cache"]
        original_db_bookinfo = package.loaded["common/db_bookinfo"]
    end)

    after_each(function()
        package.loaded.util = original_util
        package.loaded["common/cover_render_cache"] = original_render_cache
        package.loaded["common/cover_decode_cache"] = original_decode_cache
        package.loaded["common/db_bookinfo"] = original_db_bookinfo
        ZenSpec.unload("common/memory_policy")
    end)

    local function load_with_memory(available_mib, total_mib)
        ZenSpec.replace("util", {
            calcFreeMem = function()
                if not total_mib then return nil, nil end
                return available_mib * 1024 * 1024, total_mib * 1024 * 1024
            end,
        })
        ZenSpec.unload("common/memory_policy")
        return require("common/memory_policy")
    end

    it("scales cover budgets to five percent of constrained device memory", function()
        local policy = load_with_memory(80, 128)
        local profile = policy.getProfile()

        assert.is_true(profile.low_memory)
        assert.are.equal(math.floor(128 * 1024 * 1024 * 0.05), profile.cover_bytes)
        assert.are.equal(profile.cover_bytes, profile.render_bytes + profile.decode_bytes)
        assert.are.equal(math.floor(profile.cover_bytes * 0.8), profile.render_bytes)
    end)

    it("raises the cover budget when total and available memory allow it", function()
        local policy = load_with_memory(800, 1024)
        local profile = policy.getProfile()

        assert.is_false(profile.low_memory)
        assert.are.equal(math.floor(1024 * 1024 * 1024 * 0.05), profile.cover_bytes)
        assert.are.equal(profile.cover_bytes, profile.render_bytes + profile.decode_bytes)
    end)

    it("bounds cover growth by currently available memory", function()
        local policy = load_with_memory(800, 2000)
        local profile = policy.getProfile()

        assert.are.equal("normal", profile.pressure)
        assert.are.equal(80 * 1024 * 1024, profile.cover_bytes)
    end)

    it("caps the cover budget on very large devices", function()
        local policy = load_with_memory(7000, 8192)
        local profile = policy.getProfile()

        assert.are.equal(128 * 1024 * 1024, profile.cover_bytes)
        assert.are.equal(6 * 1024 * 1024, profile.home_bytes)
    end)

    it("stops speculative work and halves caches under pressure", function()
        local policy = load_with_memory(19, 100)
        local render_budget, decode_budget
        local profile = policy.applyCoverBudgets({
            setByteBudget = function(_, bytes) render_budget = bytes end,
        }, {
            setByteBudget = function(_, bytes) decode_budget = bytes end,
        })

        assert.are.equal("critical", profile.pressure)
        assert.is_false(policy.canPreload(profile))
        assert.is_false(policy.canPrewarmGroups(profile))
        assert.are.equal(math.floor(profile.render_bytes / 2), render_budget)
        assert.are.equal(math.floor(profile.decode_bytes / 2), decode_budget)
    end)

    it("keeps current defaults when memory reporting is unavailable", function()
        local policy = load_with_memory()
        local profile = policy.getProfile()

        assert.are.equal("normal", profile.pressure)
        assert.is_false(profile.low_memory)
        assert.are.equal(30 * 1024 * 1024, profile.cover_bytes)
        assert.is_true(policy.canPreload(profile))
        assert.is_true(policy.canPrewarmGroups(profile))
    end)

    it("releases speculative bitmap state before Reader opens", function()
        local policy = load_with_memory(80, 128)
        local render_budget, decode_budget, home_budget
        local invalidations = 0
        package.loaded["common/cover_render_cache"] = {
            setByteBudget = function(_, bytes) render_budget = bytes end,
        }
        package.loaded["common/cover_decode_cache"] = {
            setByteBudget = function(_, bytes) decode_budget = bytes end,
        }
        package.loaded["common/db_bookinfo"] = {
            invalidate = function() invalidations = invalidations + 1 end,
        }
        policy.registerHomeCache({
            setCoverCacheBudget = function(bytes) home_budget = bytes end,
        })

        local profile = policy.getProfile()
        policy.releaseForReader()

        assert.are.equal(math.floor(profile.render_bytes / 4), render_budget)
        assert.are.equal(0, decode_budget)
        assert.are.equal(0, home_budget)
        assert.are.equal(1, invalidations)
    end)
end)
