import WhatsappAccountStatusAPI from '../../api/whatsappAccountStatus';

const state = {
  channels: [],
  summary: {
    total: 0,
    active: 0,
    with_issues: 0,
    low_quality: 0,
  },
  alerts: [],
  currentChannelStatus: null,
  currentChannelEvents: [],
  uiFlags: {
    isFetching: false,
    isSyncing: false,
    isFetchingEvents: false,
  },
  meta: {
    currentPage: 1,
    totalPages: 0,
    totalCount: 0,
  },
};

const getters = {
  getChannels: $state => $state.channels,
  getSummary: $state => $state.summary,
  getAlerts: $state => $state.alerts,
  getCurrentChannelStatus: $state => $state.currentChannelStatus,
  getCurrentChannelEvents: $state => $state.currentChannelEvents,
  getUIFlags: $state => $state.uiFlags,
  getMeta: $state => $state.meta,
  hasAlerts: $state => $state.alerts.length > 0,
  getChannelByInboxId: $state => inboxId =>
    $state.channels.find(c => c.inbox_id === inboxId),
};

const mutations = {
  SET_CHANNELS($$state, { channels, summary }) {
    $$state.channels = channels;
    $$state.summary = summary;
  },
  SET_ALERTS($$state, alerts) {
    $$state.alerts = alerts;
  },
  SET_CURRENT_CHANNEL_STATUS($$state, status) {
    $$state.currentChannelStatus = status;
  },
  SET_CURRENT_CHANNEL_EVENTS($$state, { events, meta }) {
    $$state.currentChannelEvents = events;
    $$state.meta = {
      currentPage: meta.current_page,
      totalPages: meta.total_pages,
      totalCount: meta.total_count,
    };
  },
  APPEND_EVENTS($$state, { events, meta }) {
    $$state.currentChannelEvents = [...$$state.currentChannelEvents, ...events];
    $$state.meta = {
      currentPage: meta.current_page,
      totalPages: meta.total_pages,
      totalCount: meta.total_count,
    };
  },
  SET_UI_FLAG($$state, { flag, value }) {
    $$state.uiFlags[flag] = value;
  },
  UPDATE_CHANNEL_STATUS($$state, { inboxId, status }) {
    const index = $$state.channels.findIndex(c => c.inbox_id === inboxId);
    if (index !== -1) {
      $$state.channels[index] = { ...$$state.channels[index], ...status };
    }
  },
};

const actions = {
  async fetchAll({ commit }) {
    commit('SET_UI_FLAG', { flag: 'isFetching', value: true });
    try {
      const response = await WhatsappAccountStatusAPI.getAll();
      commit('SET_CHANNELS', response.data);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetching', value: false });
    }
  },

  async fetchAlerts({ commit }) {
    try {
      const response = await WhatsappAccountStatusAPI.getAlerts();
      commit('SET_ALERTS', response.data.alerts);
      return response.data.alerts;
    } catch (error) {
      throw error;
    }
  },

  async fetchChannelStatus({ commit }, inboxId) {
    commit('SET_UI_FLAG', { flag: 'isFetching', value: true });
    try {
      const response = await WhatsappAccountStatusAPI.getStatus(inboxId);
      commit('SET_CURRENT_CHANNEL_STATUS', response.data.status);
      commit('SET_CURRENT_CHANNEL_EVENTS', {
        events: response.data.recent_events,
        meta: { current_page: 1, total_pages: 1, total_count: response.data.recent_events.length }
      });
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetching', value: false });
    }
  },

  async syncChannelStatus({ commit }, inboxId) {
    commit('SET_UI_FLAG', { flag: 'isSyncing', value: true });
    try {
      const response = await WhatsappAccountStatusAPI.syncStatus(inboxId);
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSyncing', value: false });
    }
  },

  async fetchChannelEvents({ commit }, { inboxId, page = 1 }) {
    commit('SET_UI_FLAG', { flag: 'isFetchingEvents', value: true });
    try {
      const response = await WhatsappAccountStatusAPI.getEvents(inboxId, { page });
      if (page === 1) {
        commit('SET_CURRENT_CHANNEL_EVENTS', response.data);
      } else {
        commit('APPEND_EVENTS', response.data);
      }
      return response.data;
    } catch (error) {
      throw error;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetchingEvents', value: false });
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
