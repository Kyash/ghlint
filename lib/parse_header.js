#!/usr/bin/env node

const parseres = {
  link: value => {
    return value.split(',')
      .map(element => element.split(';').map(e => e.trim()))
      .map(([ref, ...params]) => {
        const href = new URL(ref.replace(/(^<|>$)/g, ''));
        href.toJSON = function (key) {
          this.searchParams.toJSON = function (key) {
            const o = {};
            for (const [key, value] of this) o[key] = value;
            return o;
          };
          const o = {};
          for (const key in this) if (!/^to(JSON|String)/.test(key)) o[key] = this[key];
          return o;
        };
        return {
          href,
          ...(
            params.map(param => {
              const [key, value] = param.split('=');
              return { key, value: value.replace(/(^"|"$)/g, '') };
            }).reduce((p, c) => { p[c.key] = c.value; return p; }, {})
          )
        };
      });
  }
};

(async () => {
  const buffers = [];
  for await (const chunk of process.stdin) buffers.push(chunk);
  const buffer = Buffer.concat(buffers);
  const text = buffer.toString();
  const lines = text.split(/\r?\n|\r/);
  const last = lines.pop();
  if (last) lines.push(last);
  const objects = lines
    .map(line => {
      const index = line.indexOf(':');
      if (index === -1) return line;
      const key = line.substring(0, index).toLowerCase();
      const value = line.substring(index + 1).trim();
      const parse = parseres[key] || (value => value);
      return { [key]: parse(value) };
    });
    process.stdout.write(JSON.stringify(objects));
})();
