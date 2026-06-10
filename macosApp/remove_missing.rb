require 'xcodeproj'

project_path = 'CastPigeonMac.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Remove NetworkManager.swift reference
target.source_build_phase.files_references.each do |file_ref|
  if file_ref.path == 'NetworkManager.swift'
    target.source_build_phase.remove_file_reference(file_ref)
    file_ref.remove_from_project
  end
end

project.save
puts "Removed NetworkManager.swift from project"
