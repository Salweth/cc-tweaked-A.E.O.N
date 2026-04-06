local command = {}

function command.run(context, _args)
  local tasksSvc = context.runtime.services.get("tasks")
  local tasks = tasksSvc and tasksSvc.list() or context.runtime.kernel.listTasks()

  for _, task in ipairs(tasks) do
    local filter = task.filter or "*"
    print(("%02d %-10s %-12s %-8s %s"):format(
      task.id,
      task.kind or "task",
      task.owner or task.name,
      task.status,
      filter
    ))
  end
end

return command
