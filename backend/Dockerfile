FROM node:22-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts && npm cache clean --force
COPY server.mjs relay.mjs workspaces.mjs student.html desktop-login.html ./
ENV HOST=0.0.0.0 PORT=8789 DATA_DIR=/data NODE_ENV=production
RUN mkdir /data && chown node:node /data
USER node
EXPOSE 8789
CMD ["node", "server.mjs"]
