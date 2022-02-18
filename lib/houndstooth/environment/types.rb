Dir[File.join(__dir__, '**', '*.rb')].each do |f|
    require_relative f
end
