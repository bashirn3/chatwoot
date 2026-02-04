/* global axios */
import ApiClient from './ApiClient';

class WhatsappAccountStatusAPI extends ApiClient {
  constructor() {
    super('whatsapp/account_status', { accountScoped: true });
  }

  // Get status for all WhatsApp channels
  getAll() {
    return axios.get(this.url);
  }

  // Get status for a specific inbox
  getStatus(inboxId) {
    return axios.get(`${this.url}/../${inboxId}/account_status`);
  }

  // Get alerts for channels that need attention
  getAlerts() {
    return axios.get(`${this.url}/alerts`);
  }

  // Manually sync status for an inbox
  syncStatus(inboxId) {
    return axios.post(`${this.url}/../${inboxId}/account_status/sync`);
  }

  // Get status event history for an inbox
  getEvents(inboxId, { page = 1, perPage = 25 } = {}) {
    return axios.get(`${this.url}/../${inboxId}/account_status/events`, {
      params: { page, per_page: perPage }
    });
  }
}

export default new WhatsappAccountStatusAPI();
