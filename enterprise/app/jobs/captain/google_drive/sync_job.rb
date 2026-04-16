class Captain::GoogleDrive::SyncJob < ApplicationJob
  queue_as :low

  def perform(hook)
    @hook = hook
    @account = hook.account
    @file_service = Captain::GoogleDrive::FileService.new(hook)
    @assistant_id = hook.settings['assistant_id']

    return unless @assistant_id.present?

    assistant = @account.captain_assistants.find_by(id: @assistant_id)
    return unless assistant

    @assistant = assistant
    folder_id = hook.settings['folder_id'].presence

    sync_files(folder_id)
    update_last_synced
    schedule_next_sync
  end

  private

  def sync_files(folder_id)
    files = @file_service.list_files(folder_id: folder_id)

    files.each do |file|
      process_file(file)
    rescue StandardError => e
      Rails.logger.error("Google Drive sync failed for file #{file.id}: #{e.message}")
    end
  end

  def process_file(file)
    external_link = "gdrive://#{file.id}"
    existing = @assistant.documents.find_by(external_link: external_link)

    if existing
      update_if_modified(existing, file)
    else
      import_file(file, external_link)
    end
  end

  def update_if_modified(document, file)
    return unless file.modified_time.present?
    return unless file.modified_time > document.updated_at

    downloaded = @file_service.download_file(file)

    case downloaded[:type]
    when :text
      document.update!(content: downloaded[:content], status: :in_progress)
      document.update!(status: :available)
    when :binary
      attach_pdf(document, downloaded)
      document.update!(status: :in_progress)
      Captain::Documents::CrawlJob.perform_later(document)
    end
  end

  def import_file(file, external_link)
    downloaded = @file_service.download_file(file)

    case downloaded[:type]
    when :text
      import_text_file(downloaded, external_link, file)
    when :binary
      import_binary_file(downloaded, external_link, file)
    end
  end

  def import_text_file(downloaded, external_link, file)
    @assistant.documents.create!(
      external_link: external_link,
      name: downloaded[:name],
      content: downloaded[:content],
      status: :available,
      metadata: { 'source' => 'google_drive', 'drive_file_id' => file.id, 'drive_modified_time' => file.modified_time&.iso8601 }
    )
  end

  def import_binary_file(downloaded, external_link, file)
    document = @assistant.documents.new(
      external_link: external_link,
      name: downloaded[:name],
      status: :in_progress,
      metadata: { 'source' => 'google_drive', 'drive_file_id' => file.id, 'drive_modified_time' => file.modified_time&.iso8601 }
    )
    attach_pdf(document, downloaded)
    document.save!
  end

  def attach_pdf(document, downloaded)
    document.pdf_file.attach(
      io: downloaded[:content],
      filename: "#{downloaded[:name]}.pdf",
      content_type: downloaded[:mime_type] || 'application/pdf'
    )
  end

  def update_last_synced
    @hook.update!(
      settings: @hook.settings.merge('last_synced_at' => Time.current.iso8601)
    )
  end

  def schedule_next_sync
    interval = (@hook.settings['sync_interval_hours'] || 6).to_i.hours
    self.class.set(wait: interval).perform_later(@hook)
  end
end
