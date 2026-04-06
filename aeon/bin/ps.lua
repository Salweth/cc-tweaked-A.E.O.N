local command = {}

function command.run(context, _args)
  local tasks = context.runtime.kernel.listTasks()

  for _, task in ipairs(tasks) do
    local filter = task.filter or "*"
    print(("%02d %-18s %-8s %s"):format(task.id, task.name, task.status, filter))
  end
end

return command
