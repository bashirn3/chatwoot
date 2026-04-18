# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :temperature

  def initialize
    Llm::Config.initialize!
    setup_model
    setup_temperature
  end

  def chat(model: @model, temperature: @temperature)
    chat_args = { model: model }
    if custom_endpoint?
      chat_args[:provider] = :openai
      chat_args[:assume_model_exists] = true
    end
    RubyLLM.chat(**chat_args).with_temperature(temperature)
  end

  private

  def custom_endpoint?
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence ||
               ENV.fetch('CAPTAIN_OPEN_AI_ENDPOINT', nil).presence
    endpoint.present? && !endpoint.include?('api.openai.com')
  end

  def setup_model
    config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
                   ENV.fetch('CAPTAIN_OPEN_AI_MODEL', nil)
    @model = (config_value.presence || DEFAULT_MODEL)
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
