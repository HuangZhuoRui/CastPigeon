require 'xcodeproj'

project_path = 'CastPigeonMac.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Helper to find or create a group
def get_or_create_group(parent_group, group_name)
  group = parent_group.groups.find { |g| g.name == group_name || g.path == group_name }
  if group.nil?
    group = parent_group.new_group(group_name, group_name)
  end
  group
end

main_group = project.main_group.groups.find { |g| g.name == 'CastPigeonMac' || g.path == 'CastPigeonMac' }

['Models', 'Network', 'ViewModels'].each do |dir|
  group = get_or_create_group(main_group, dir)
  
  Dir.glob("CastPigeonMac/#{dir}/*.swift").each do |file_path|
    file_name = File.basename(file_path)
    
    # Check if file is already in the group
    file_ref = group.files.find { |f| f.path == file_name }
    if file_ref.nil?
      file_ref = group.new_file(file_name)
    end
    
    # Add to target's source build phase if not already there
    if target.source_build_phase.files_references.include?(file_ref) == false
      target.add_file_references([file_ref])
    end
  end
end

project.save
puts "Successfully added files to Xcode project"
