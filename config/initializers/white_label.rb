require 'white_label_config'

Rails.application.config.after_initialize do
  WhiteLabelConfig.config
end
