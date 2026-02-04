# frozen_string_literal: true

json.id template.id
json.name template.name
json.language template.language
json.language_name WhatsappTemplate::SUPPORTED_LANGUAGES[template.language]
json.category template.category
json.status template.status
json.quality_score template.quality_score
json.rejection_reason template.rejection_reason

json.header_type template.header_type
json.header_content template.header_content
json.header_params template.header_params
json.header_variable_count template.header_variable_count

json.body_text template.body_text
json.body_params template.body_params
json.body_variable_count template.body_variable_count

json.footer_text template.footer_text
json.buttons template.buttons

if template.header_location?
  json.location do
    json.latitude template.location_latitude
    json.longitude template.location_longitude
    json.name template.location_name
    json.address template.location_address
  end
end

json.meta_template_id template.meta_template_id
json.channel_whatsapp_id template.channel_whatsapp_id
json.clerk_organization_id template.clerk_organization_id
json.user_id template.user_id

json.editable template.editable?
json.submittable template.submittable?

json.submitted_at template.submitted_at
json.approved_at template.approved_at
json.rejected_at template.rejected_at
json.last_synced_at template.last_synced_at
json.created_at template.created_at
json.updated_at template.updated_at
