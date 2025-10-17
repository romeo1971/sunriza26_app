FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --ignore-scripts

FROM node:20-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/dist ./dist
COPY package.json .
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser
EXPOSE 3001
ENV PORT=3001
CMD ["node", "dist/lipsync_handler.js"]



