// Dev-server proxy for `npm start`. Points at a local GridStream server by default;
// set GRIDSTREAM_SERVER (e.g. http://my-mac.local:8080) to use another machine.
export default {
  '/api': {
    target: process.env.GRIDSTREAM_SERVER ?? 'http://localhost:8080',
    secure: false,
    changeOrigin: true,
  },
};
