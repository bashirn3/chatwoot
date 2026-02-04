<script setup>
import { computed } from 'vue';

const props = defineProps({
  template: {
    type: Object,
    required: true,
  },
  sampleValues: {
    type: Object,
    default: () => ({}),
  },
});

const previewHeader = computed(() => {
  if (!props.template.header_type || props.template.header_type === 'TEXT') {
    if (!props.template.header_content) return null;
    let text = props.template.header_content;
    Object.entries(props.sampleValues.header || {}).forEach(([key, value]) => {
      text = text.replace(`{{${key}}}`, value || `[Var ${key}]`);
    });
    return { type: 'text', content: text };
  }
  return { type: props.template.header_type?.toLowerCase(), content: props.template.header_content };
});

const previewBody = computed(() => {
  let text = props.template.body_text || '';
  Object.entries(props.sampleValues.body || {}).forEach(([key, value]) => {
    text = text.replace(`{{${key}}}`, value || `[Var ${key}]`);
  });
  return text;
});

const previewFooter = computed(() => props.template.footer_text);

const previewButtons = computed(() => props.template.buttons || []);

const currentTime = computed(() => {
  const now = new Date();
  return now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
});

const formatBody = (text) => {
  if (!text) return '';
  return text
    .replace(/\n/g, '<br>')
    .replace(/\*([^*]+)\*/g, '<strong>$1</strong>')
    .replace(/_([^_]+)_/g, '<em>$1</em>');
};
</script>

<template>
  <div class="whatsapp-preview">
    <div class="preview-header">
      <span class="preview-title">Preview</span>
    </div>
    
    <div class="preview-container">
      <div class="chat-background">
        <div class="message-bubble">
          <!-- Tail -->
          <div class="bubble-tail"></div>
          
          <!-- Header -->
          <div v-if="previewHeader" class="message-header">
            <template v-if="previewHeader.type === 'text'">
              <div class="header-text">{{ previewHeader.content }}</div>
            </template>
            <template v-else-if="previewHeader.type === 'image'">
              <div class="header-media">
                <div class="media-placeholder">
                  <span class="i-lucide-image w-8 h-8" />
                  <span>Image</span>
                </div>
              </div>
            </template>
            <template v-else-if="previewHeader.type === 'video'">
              <div class="header-media">
                <div class="media-placeholder">
                  <span class="i-lucide-video w-8 h-8" />
                  <span>Video</span>
                </div>
              </div>
            </template>
            <template v-else-if="previewHeader.type === 'document'">
              <div class="header-media">
                <div class="media-placeholder">
                  <span class="i-lucide-file-text w-8 h-8" />
                  <span>Document</span>
                </div>
              </div>
            </template>
            <template v-else-if="previewHeader.type === 'location'">
              <div class="header-media">
                <div class="media-placeholder">
                  <span class="i-lucide-map-pin w-8 h-8" />
                  <span>{{ template.location_name || 'Location' }}</span>
                </div>
              </div>
            </template>
          </div>
          
          <!-- Body -->
          <div class="message-body">
            <p class="body-text" v-html="formatBody(previewBody)"></p>
          </div>
          
          <!-- Footer -->
          <div v-if="previewFooter" class="message-footer">
            {{ previewFooter }}
          </div>
          
          <!-- Timestamp -->
          <div class="message-time">
            {{ currentTime }}
          </div>
          
          <!-- Buttons -->
          <div v-if="previewButtons.length > 0" class="message-buttons">
            <div 
              v-for="(button, index) in previewButtons" 
              :key="index"
              class="button-item"
            >
              <span 
                v-if="button.type === 'URL'" 
                class="i-lucide-external-link w-3.5 h-3.5" 
              />
              <span 
                v-else-if="button.type === 'PHONE_NUMBER'" 
                class="i-lucide-phone w-3.5 h-3.5" 
              />
              <span 
                v-else-if="button.type === 'COPY_CODE'" 
                class="i-lucide-copy w-3.5 h-3.5" 
              />
              <span>{{ button.text || 'Button' }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.whatsapp-preview {
  background-color: #f0f2f5;
  border-radius: 12px;
  overflow: hidden;
  min-width: 320px;
  max-width: 360px;
}

.preview-header {
  background-color: #075e54;
  color: white;
  padding: 12px 16px;
  font-weight: 500;
}

.preview-title {
  font-size: 14px;
}

.preview-container {
  padding: 16px;
}

.chat-background {
  background-color: #e5ddd5;
  background-image: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAyCAYAAAAeP4ixAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAhGVYSWZNTQAqAAAACAAFARIAAwAAAAEAAQAAARoABQAAAAEAAABKARsABQAAAAEAAABSASgAAwAAAAEAAgAAh2kABAAAAAEAAABaAAAAAAAAAEgAAAABAAAASAAAAAEAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAMqADAAQAAAABAAAAMgAAAABVjfJvAAAACXBIWXMAAAsTAAALEwEAmpwYAAABWWlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNi4wLjAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp0aWZmPSJodHRwOi8vbnMuYWRvYmUuY29tL3RpZmYvMS4wLyI+CiAgICAgICAgIDx0aWZmOk9yaWVudGF0aW9uPjE8L3RpZmY6T3JpZW50YXRpb24+CiAgICAgIDwvcmRmOkRlc2NyaXB0aW9uPgogICA8L3JkZjpSREY+CjwveDp4bXBtZXRhPgoZXuEHAAAAWUlEQVRoBe3WMQEAAAjDMLV/jzFBCFmYsGfl68Yv7gECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAIHdATJ8AEHUPmK5AAAAAElFTkSuQmCC");
  border-radius: 8px;
  padding: 16px;
  min-height: 200px;
}

.message-bubble {
  background-color: white;
  border-radius: 7.5px;
  border-top-left-radius: 0;
  box-shadow: 0 1px 0.5px rgba(0, 0, 0, 0.13);
  max-width: 280px;
  position: relative;
  word-wrap: break-word;
}

.bubble-tail {
  position: absolute;
  top: -6px;
  left: -12px;
  width: 12px;
  height: 31px;
  background-image: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAwAAAAfCAYAAABxbkhWAAAAAXNSR0IArs4c6QAAAAlwSFlzAAALEwAACxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAANRJREFUOBFj+M8w9T8DEDAyMjAcBGFQiAHE/g9iE0NjYGJiYgIpAipmYWZhYQFx/sOECSpkgiqGKQPxsSkk6gaQJpg4NjOI0kio5kOHDhGlh6hmYGJmYvwPFCBa8z9GPVEqCGmiSjRAFdH2JKqJKIQIlALqAgJlVKnDqhA/C1YNOPmIK4CrwKkIOxO5GnBqIKgQLw9BD0HVQFMBVIxwMCHVQD0BVE1fO1E2YFNIjDyyjf9B4kShQJVAQKKMmhoIaSJGgmgNoABRXiAUQYwCcgcBYvxA0GYAYtMT2j2g3TQAAAAASUVORK5CYII=");
  background-size: contain;
}

.message-header {
  padding: 0;
}

.header-text {
  color: rgba(0, 0, 0, 0.76);
  font-size: 15px;
  font-weight: 600;
  line-height: 19px;
  padding: 6px 9px 0;
}

.header-media {
  padding: 3px;
}

.media-placeholder {
  background-color: #ccd0d5;
  border-radius: 4px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 100px;
  color: #666;
  gap: 8px;
}

.message-body {
  padding: 7px 9px 6px;
}

.body-text {
  color: #262626;
  font-size: 14px;
  line-height: 19px;
  margin: 0;
  white-space: pre-wrap;
}

.message-footer {
  color: rgba(0, 0, 0, 0.45);
  font-size: 13px;
  line-height: 17px;
  padding: 0 9px 8px;
}

.message-time {
  position: absolute;
  bottom: 4px;
  right: 8px;
  color: rgba(0, 0, 0, 0.4);
  font-size: 11px;
}

.message-buttons {
  border-top: 1px solid #dadde1;
}

.button-item {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: #00a5f4;
  font-size: 14px;
  padding: 12px;
  border-bottom: 1px solid #dadde1;
  cursor: pointer;
}

.button-item:last-child {
  border-bottom: none;
}

.button-item:hover {
  background-color: #f5f5f5;
}
</style>
