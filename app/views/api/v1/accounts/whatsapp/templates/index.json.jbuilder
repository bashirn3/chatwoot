# frozen_string_literal: true

json.payload do
  json.array! @templates do |template|
    json.partial! 'api/v1/accounts/whatsapp/templates/template', template: template
  end
end

json.meta do
  json.count @templates.count
  json.current_page @templates.current_page
  json.total_pages @templates.total_pages
  json.total_count @templates.total_count
end
