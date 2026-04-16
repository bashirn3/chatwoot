/* global axios */
import ApiClient from '../ApiClient';

class CaptainGoogleDrive extends ApiClient {
  constructor() {
    super('captain/google_drive', { accountScoped: true });
  }

  status() {
    return axios.get(this.url);
  }

  authorize(assistantId, folderId = null) {
    return axios.post(this.url, {
      assistant_id: assistantId,
      folder_id: folderId,
    });
  }

  disconnect() {
    return axios.delete(this.url);
  }

  sync() {
    return axios.post(`${this.url}/sync`);
  }
}

export default new CaptainGoogleDrive();
