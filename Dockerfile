FROM node:20.18.0-alpine

# Install bash and any required tools
RUN apk add --no-cache bash

# Install global dependencies
RUN npm i -g @nestjs/cli typescript ts-node

# Set the working directory
WORKDIR /src/

# Copy package.json and package-lock.json to install dependencies
COPY package*.json ./
RUN npm install

# Copy the entire application code
COPY . .

# Build the application (compile TypeScript to JavaScript)
RUN npm run build



# Set the CMD to use Lambda handler
CMD ["dist/main.js"]  # Update path if different
