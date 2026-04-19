/* global axios */
import ApiClient from './ApiClient';

class WhatsAppBridgeAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: false });
  }

  get url() {
    return `/api/v1/whatsapp_bridge/accounts/${this.accountIdFromRoute}`;
  }

  createInstance(instanceName, { countryIso = null, regionCode = null } = {}) {
    return axios.post(`${this.url}/create_instance`, {
      instance_name: instanceName,
      country_iso: countryIso,
      region_code: regionCode,
    });
  }

  getRegions() {
    return axios.get(`${this.url}/regions`);
  }

  resolveRegion(countryIso) {
    return axios.post(`${this.url}/resolve_region`, {
      country_iso: countryIso,
    });
  }

  // Liveness probe for a region / freshly-created instance. The country
  // picker polls this after provisioning to confirm the framework is
  // reachable before sending the admin to the QR scan step.
  regionHealth({ regionCode, instanceName = null }) {
    const params = new URLSearchParams({ region_code: regionCode });
    if (instanceName) params.append('instance_name', instanceName);
    return axios.get(`${this.url}/region_health?${params.toString()}`);
  }

  connect(instanceName, pairingPhone = null) {
    const body = pairingPhone ? { pairing_phone: pairingPhone } : {};
    return axios.post(`${this.url}/connect/${instanceName}`, body);
  }

  qrCode(instanceName) {
    return axios.get(`${this.url}/qr/${instanceName}`);
  }

  connectionState(instanceName) {
    return axios.get(`${this.url}/connection/${instanceName}`);
  }

  getInstances() {
    return axios.get(`${this.url}/instances`);
  }

  disconnect(instanceName) {
    return axios.post(`${this.url}/disconnect/${instanceName}`);
  }

  deleteInstance(instanceName) {
    return axios.delete(`${this.url}/delete/${instanceName}`);
  }

  relinkInstance(instanceName) {
    return axios.post(`${this.url}/relink/${instanceName}`);
  }

  deleteInbox(inboxId) {
    return axios.delete(`${this.url}/inbox/${inboxId}`);
  }

  getInstanceDetail(instanceName) {
    return axios.get(`${this.url}/instance_detail/${instanceName}`);
  }

  updateInstance(instanceName, data) {
    return axios.put(`${this.url}/update_instance/${instanceName}`, data);
  }

  getAntiBan(instanceName) {
    return axios.get(`${this.url}/anti_ban/${instanceName}`);
  }

  updateAntiBan(instanceName, data) {
    return axios.put(`${this.url}/anti_ban/${instanceName}`, data);
  }

  getBehavior(instanceName) {
    return axios.get(`${this.url}/behavior/${instanceName}`);
  }

  updateBehavior(instanceName, data) {
    return axios.put(`${this.url}/behavior/${instanceName}`, data);
  }

  getProfile(instanceName) {
    return axios.get(`${this.url}/profile/${instanceName}`);
  }

  updateProfileName(instanceName, name) {
    return axios.put(`${this.url}/profile_name/${instanceName}`, { name });
  }

  updateProfilePicture(instanceName, imageUrl) {
    return axios.put(`${this.url}/profile_picture/${instanceName}`, {
      imageUrl,
    });
  }

  updateProfileStatus(instanceName, status) {
    return axios.put(`${this.url}/profile_status/${instanceName}`, { status });
  }

  getHandoff(instanceName) {
    return axios.get(`${this.url}/handoff/${instanceName}`);
  }

  updateHandoff(instanceName, data) {
    return axios.post(`${this.url}/handoff/${instanceName}`, data);
  }

  getHandoffSettings(instanceName) {
    return axios.get(`${this.url}/handoff_settings/${instanceName}`);
  }

  updateHandoffSettings(instanceName, data) {
    return axios.put(`${this.url}/handoff_settings/${instanceName}`, data);
  }
}

export default new WhatsAppBridgeAPI();
