/* global axios */
import ApiClient from './ApiClient';

class WhatsappTemplatesAPI extends ApiClient {
  constructor() {
    super('whatsapp/templates', { accountScoped: true });
  }

  // Get all templates with optional filters
  getAll({ page = 1, perPage = 25, status, category, search, channelId } = {}) {
    const params = {
      page,
      per_page: perPage,
      ...(status && { status }),
      ...(category && { category }),
      ...(search && { search }),
      ...(channelId && { channel_id: channelId }),
    };
    return axios.get(this.url, { params });
  }

  // Get single template
  get(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // Create new template
  create(templateData) {
    return axios.post(this.url, { template: templateData });
  }

  // Update template
  update(id, templateData) {
    return axios.patch(`${this.url}/${id}`, { template: templateData });
  }

  // Delete template
  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // Submit template to Meta for approval
  submit(id) {
    return axios.post(`${this.url}/${id}/submit`);
  }

  // Submit template to multiple WhatsApp channels
  submitToChannels(id, channelIds) {
    return axios.post(`${this.url}/${id}/submit_to_channels`, { channel_ids: channelIds });
  }

  // Sync template status from Meta
  sync(id) {
    return axios.post(`${this.url}/${id}/sync`);
  }

  // Reset template to draft status
  resetToDraft(id) {
    return axios.post(`${this.url}/${id}/reset_to_draft`);
  }

  // Get list of WhatsApp channels
  getChannels() {
    return axios.get(`${this.url}/channels`);
  }

  // Sync all templates from Meta
  syncAll(channelId) {
    const params = channelId ? { channel_id: channelId } : {};
    return axios.post(`${this.url}/sync_all`, params);
  }

  // Get supported languages
  getLanguages() {
    return axios.get(`${this.url}/languages`);
  }

  // Get sample templates
  getSamples() {
    return axios.get(`${this.url}/sample`);
  }
}

export default new WhatsappTemplatesAPI();
