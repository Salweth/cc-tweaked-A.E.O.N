local driver = { id = "cc.speaker" }

function driver.match(entry, helpers)
  return helpers.hasType(entry, "speaker")
    and helpers.hasMethods(entry, { "playNote", "playSound", "playAudio", "stop" })
end

function driver.bindCapabilities(entry)
  return { speaker = entry.object }
end

return driver
