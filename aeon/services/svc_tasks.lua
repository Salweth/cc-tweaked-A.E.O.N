local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")

local service = define({
  name = "tasks",
  essential = true,
  start = function(context)
    context.log.info("service online")

    local function listTasks()
      return context.runtime.kernel.listTasks()
    end

    context.on(events.global("service.started"), function()
      context.emit(events.global("tasks.changed"), "service_started")
    end)

    context.on(events.global("service.stopped"), function()
      context.emit(events.global("tasks.changed"), "service_stopped")
    end)

    return {
      list = function()
        local tasks = {}

        for _, task in ipairs(listTasks()) do
          table.insert(tasks, {
            id = task.id,
            name = task.name,
            status = task.status,
            filter = task.filter,
            owner = task.owner,
            kind = task.kind,
          })
        end

        return tasks
      end,
      get = function(taskId)
        for _, task in ipairs(listTasks()) do
          if task.id == taskId then
            return task
          end
        end

        return nil
      end,
    }
  end,
})

return service
