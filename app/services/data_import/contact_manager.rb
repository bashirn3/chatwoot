class DataImport::ContactManager
  # Column name mappings - maps various CSV column names to our standard field names
  COLUMN_MAPPINGS = {
    email: %w[email e-mail email_address emailaddress mail],
    phone_number: %w[phone_number phonenumber phone phone_no mobile mobile_number cell cellphone telephone tel],
    identifier: %w[identifier id external_id externalid customer_id customerid user_id userid],
    name: %w[name full_name fullname contact_name contactname customer_name customername first_name firstname],
    company: %w[company company_name companyname organization organisation org business],
    city: %w[city location town]
  }.freeze

  def initialize(account)
    @account = account
  end

  def build_contact(params)
    # Normalize params keys to handle different column name variations
    normalized_params = normalize_params(params)
    contact = find_or_initialize_contact(normalized_params)
    update_contact_attributes(normalized_params, contact)
    contact
  end

  def find_or_initialize_contact(params)
    contact = find_existing_contact(params)
    contact_params = params.slice(:email, :identifier, :phone_number)
    contact_params[:phone_number] = format_phone_number(contact_params[:phone_number]) if contact_params[:phone_number].present?
    contact ||= @account.contacts.new(contact_params)
    contact
  end

  # Normalize column names from CSV to our standard field names
  def normalize_params(params)
    normalized = {}
    remaining_params = params.dup

    COLUMN_MAPPINGS.each do |standard_key, variations|
      # Check each variation (case-insensitive)
      variations.each do |variation|
        matching_key = params.keys.find { |k| k.to_s.downcase.strip == variation.downcase }
        if matching_key && params[matching_key].present?
          normalized[standard_key] = params[matching_key].to_s.strip
          remaining_params.delete(matching_key)
          break
        end
      end
    end

    # Add any remaining columns as custom attributes (excluding known non-attribute columns)
    excluded_keys = %w[id ip_address created_at updated_at errors]
    remaining_params.each do |key, value|
      next if excluded_keys.include?(key.to_s.downcase)
      next if value.blank?
      next if COLUMN_MAPPINGS.values.flatten.include?(key.to_s.downcase)

      # Add as custom attribute with normalized key
      normalized[key.to_s.downcase.gsub(/\s+/, '_').to_sym] = value.to_s.strip
    end

    normalized.with_indifferent_access
  end

  def find_existing_contact(params)
    contact = find_contact_by_identifier(params)
    contact ||= find_contact_by_email(params)
    contact ||= find_contact_by_phone_number(params)

    update_contact_with_merged_attributes(params, contact) if contact.present? && contact.valid?
    contact
  end

  def find_contact_by_identifier(params)
    return unless params[:identifier]

    @account.contacts.find_by(identifier: params[:identifier])
  end

  def find_contact_by_email(params)
    return unless params[:email]

    @account.contacts.from_email(params[:email])
  end

  def find_contact_by_phone_number(params)
    return unless params[:phone_number]

    @account.contacts.find_by(phone_number: format_phone_number(params[:phone_number]))
  end

  def update_contact_with_merged_attributes(params, contact)
    contact.identifier = params[:identifier] if params[:identifier].present?
    contact.email = params[:email] if params[:email].present?
    contact.phone_number = format_phone_number(params[:phone_number]) if params[:phone_number].present?
    update_contact_attributes(params, contact)
    contact.save
  end

  private

  # Standard fields that should not be added as custom attributes
  STANDARD_FIELDS = %i[identifier email name phone_number company city].freeze

  def update_contact_attributes(params, contact)
    contact.name = params[:name] if params[:name].present?
    contact.additional_attributes ||= {}
    contact.additional_attributes[:company] = params[:company] if params[:company].present?
    contact.additional_attributes[:city] = params[:city] if params[:city].present?

    # Add remaining params as custom attributes, excluding standard fields
    custom_attrs = params.except(*STANDARD_FIELDS).reject { |_, v| v.blank? }
    contact.assign_attributes(custom_attributes: (contact.custom_attributes || {}).merge(custom_attrs)) if custom_attrs.any?
  end

  def format_phone_number(phone_number)
    return nil if phone_number.blank?

    phone_str = phone_number.to_s.strip
    # Remove any non-digit characters except the leading +
    cleaned = phone_str.gsub(/[^\d+]/, '')
    cleaned.start_with?('+') ? cleaned : "+#{cleaned}"
  end
end
