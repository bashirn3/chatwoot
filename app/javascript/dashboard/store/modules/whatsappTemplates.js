import WhatsappTemplatesAPI from '../../api/whatsappTemplates';

const state = {
  records: [],
  channels: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isSubmitting: false,
    isSyncing: false,
    isFetchingChannels: false,
  },
  meta: {
    count: 0,
    currentPage: 1,
    totalPages: 0,
    totalCount: 0,
  },
  languages: {},
  samples: {},
};

const getters = {
  getTemplates: $state => $state.records,
  getChannels: $state => $state.channels,
  getUIFlags: $state => $state.uiFlags,
  getMeta: $state => $state.meta,
  getLanguages: $state => $state.languages,
  getSamples: $state => $state.samples,
  getTemplateById: $state => id => $state.records.find(t => t.id === id),
  getTemplatesByStatus: $state => status =>
    $state.records.filter(t => t.status === status),
  getApprovedTemplates: $state =>
    $state.records.filter(t => t.status === 'APPROVED'),
  getDraftTemplates: $state =>
    $state.records.filter(t => t.status === 'DRAFT'),
  getPendingTemplates: $state =>
    $state.records.filter(t => t.status === 'PENDING'),
};

const mutations = {
  SET_TEMPLATES($$state, templates) {
    $$state.records = templates;
  },
  ADD_TEMPLATE($$state, template) {
    const index = $$state.records.findIndex(t => t.id === template.id);
    if (index === -1) {
      $$state.records.push(template);
    } else {
      $$state.records[index] = template;
    }
  },
  UPDATE_TEMPLATE($$state, template) {
    const index = $$state.records.findIndex(t => t.id === template.id);
    if (index !== -1) {
      $$state.records[index] = template;
    }
  },
  DELETE_TEMPLATE($$state, templateId) {
    $$state.records = $$state.records.filter(t => t.id !== templateId);
  },
  SET_CHANNELS($$state, channels) {
    $$state.channels = channels;
  },
  SET_UI_FLAG($$state, { flag, value }) {
    $$state.uiFlags[flag] = value;
  },
  SET_META($$state, meta) {
    $$state.meta = {
      count: meta.count || 0,
      currentPage: meta.current_page || 1,
      totalPages: meta.total_pages || 0,
      totalCount: meta.total_count || 0,
    };
  },
  SET_LANGUAGES($$state, languages) {
    $$state.languages = languages;
  },
  SET_SAMPLES($$state, samples) {
    $$state.samples = samples;
  },
};

const actions = {
  async fetchTemplates({ commit }, params = {}) {
    commit('SET_UI_FLAG', { flag: 'isFetching', value: true });
    try {
      const response = await WhatsappTemplatesAPI.getAll(params);
      commit('SET_TEMPLATES', response.data.payload);
      commit('SET_META', response.data.meta);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetching', value: false });
    }
  },

  async fetchTemplate({ commit }, templateId) {
    commit('SET_UI_FLAG', { flag: 'isFetching', value: true });
    try {
      const response = await WhatsappTemplatesAPI.get(templateId);
      commit('UPDATE_TEMPLATE', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetching', value: false });
    }
  },

  async createTemplate({ commit }, templateData) {
    commit('SET_UI_FLAG', { flag: 'isCreating', value: true });
    try {
      const response = await WhatsappTemplatesAPI.create(templateData);
      commit('ADD_TEMPLATE', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isCreating', value: false });
    }
  },

  async updateTemplate({ commit }, { id, ...templateData }) {
    commit('SET_UI_FLAG', { flag: 'isUpdating', value: true });
    try {
      const response = await WhatsappTemplatesAPI.update(id, templateData);
      commit('UPDATE_TEMPLATE', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isUpdating', value: false });
    }
  },

  async deleteTemplate({ commit }, templateId) {
    commit('SET_UI_FLAG', { flag: 'isDeleting', value: true });
    try {
      await WhatsappTemplatesAPI.delete(templateId);
      commit('DELETE_TEMPLATE', templateId);
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isDeleting', value: false });
    }
  },

  async submitTemplate({ commit }, templateId) {
    commit('SET_UI_FLAG', { flag: 'isSubmitting', value: true });
    try {
      const response = await WhatsappTemplatesAPI.submit(templateId);
      commit('UPDATE_TEMPLATE', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSubmitting', value: false });
    }
  },

  async syncTemplate({ commit }, templateId) {
    commit('SET_UI_FLAG', { flag: 'isSyncing', value: true });
    try {
      const response = await WhatsappTemplatesAPI.sync(templateId);
      commit('UPDATE_TEMPLATE', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSyncing', value: false });
    }
  },

  async resetToDraft({ commit }, templateId) {
    commit('SET_UI_FLAG', { flag: 'isUpdating', value: true });
    try {
      const response = await WhatsappTemplatesAPI.resetToDraft(templateId);
      commit('UPDATE_TEMPLATE', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isUpdating', value: false });
    }
  },

  async syncAllTemplates({ commit, dispatch }, channelId) {
    commit('SET_UI_FLAG', { flag: 'isSyncing', value: true });
    try {
      await WhatsappTemplatesAPI.syncAll(channelId);
      // Refresh the templates list after sync
      await dispatch('fetchTemplates');
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSyncing', value: false });
    }
  },

  async duplicateTemplate({ commit }, { templateId, newName }) {
    commit('SET_UI_FLAG', { flag: 'isCreating', value: true });
    try {
      const response = await WhatsappTemplatesAPI.duplicate(templateId, newName);
      commit('ADD_TEMPLATE', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isCreating', value: false });
    }
  },

  async importFromMeta({ commit, dispatch }) {
    commit('SET_UI_FLAG', { flag: 'isSyncing', value: true });
    try {
      const response = await WhatsappTemplatesAPI.importFromMeta();
      // Refresh the templates list after import
      await dispatch('fetchTemplates');
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSyncing', value: false });
    }
  },

  async fetchLanguages({ commit }) {
    try {
      const response = await WhatsappTemplatesAPI.getLanguages();
      commit('SET_LANGUAGES', response.data);
      return response.data;
    } catch (error) {
      throw error;
    }
  },

  async fetchSamples({ commit }) {
    try {
      const response = await WhatsappTemplatesAPI.getSamples();
      commit('SET_SAMPLES', response.data);
      return response.data;
    } catch (error) {
      throw error;
    }
  },

  async fetchChannels({ commit }) {
    commit('SET_UI_FLAG', { flag: 'isFetchingChannels', value: true });
    try {
      const response = await WhatsappTemplatesAPI.getChannels();
      commit('SET_CHANNELS', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetchingChannels', value: false });
    }
  },

  async submitToChannels({ commit }, { templateId, channelIds }) {
    commit('SET_UI_FLAG', { flag: 'isSubmitting', value: true });
    try {
      const response = await WhatsappTemplatesAPI.submitToChannels(templateId, channelIds);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSubmitting', value: false });
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
