export const DICEBEAR_STYLES = [
  'adventurer',
  'avataaars',
  'big-smile',
  'bottts',
  'fun-emoji',
  'lorelei',
  'micah',
  'miniavs',
  'notionists',
  'open-peeps',
  'personas',
  'pixel-art',
  'thumbs',
  'glass',
  'shapes',
  'rings',
  'identicon',
  'initials',
];

export function dicebearAvatarUrl(name, style = 'adventurer') {
  if (!name) return '';
  const seed = encodeURIComponent(name);
  return `https://api.dicebear.com/9.x/${style}/svg?seed=${seed}&radius=50`;
}
