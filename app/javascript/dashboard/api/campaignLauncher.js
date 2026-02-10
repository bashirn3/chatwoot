/* global axios */
import ApiClient from './ApiClient';

class CampaignLauncherAPI extends ApiClient {
  constructor() {
    super('campaign_launcher', { accountScoped: true });
  }

  uploadCsv(file) {
    const formData = new FormData();
    formData.append('file', file);
    return axios.post(`${this.url}/upload_csv`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  getWhatsAppInboxes() {
    return axios.get(`${this.url}/whatsapp_inboxes`);
  }

  validate(payload) {
    return axios.post(`${this.url}/validate`, payload);
  }

  // Returns an EventSource URL for SSE streaming
  getLaunchUrl() {
    return `${this.url}/launch`;
  }
}

export default new CampaignLauncherAPI();
