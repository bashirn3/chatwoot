/* global axios */
import ApiClient from './ApiClient';

class TypebotsAPI extends ApiClient {
  constructor() {
    super('typebots', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  create(name) {
    return axios.post(this.url, { name });
  }

  get(id) {
    return axios.get(`${this.url}/${id}`);
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  assign(id, inboxId) {
    return axios.post(`${this.url}/${id}/assign`, { inbox_id: inboxId });
  }

  unassign(id, inboxId) {
    return axios.delete(`${this.url}/${id}/unassign`, {
      data: { inbox_id: inboxId },
    });
  }

  getEditorSession(id) {
    return axios.get(`${this.url}/${id}/editor`);
  }

  toggleBot(conversationId) {
    return axios.post(`${this.url}/toggle_bot`, {
      conversation_id: conversationId,
    });
  }
}

export default new TypebotsAPI();
