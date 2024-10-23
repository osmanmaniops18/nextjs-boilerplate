import 'dotenv/config';
import {
  ClassSerializerInterceptor,
  ValidationPipe,
  VersioningType,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory, Reflector } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { useContainer } from 'class-validator';
import { AppModule } from './app.module';
import express, { Handler } from 'express';
import { createServer, proxy } from 'aws-serverless-express';
import { APIGatewayEvent, Context } from 'aws-lambda';
import validationOptions from './utils/validation-options';
import { AllConfigType } from './config/config.type';
import { ResolvePromisesInterceptor } from './utils/serializer.interceptor';
import { Server } from 'http';

const expressApp = express();
let cachedServer: Server;
let isColdStart = true;
const logger = new Logger('LambdaBootstrap'); // Logger for logging errors

async function bootstrap() {
  try {
    logger.log('Initializing NestJS application...');
    const app = await NestFactory.create(AppModule, { cors: true });

    useContainer(app.select(AppModule), { fallbackOnErrors: true });

    const configService = app.get(ConfigService<AllConfigType>);

    app.enableShutdownHooks();
    app.setGlobalPrefix(
      configService.getOrThrow('app.apiPrefix', { infer: true }),
      {
        exclude: ['/prod/'],
      },
    );
    app.enableVersioning({
      type: VersioningType.URI,
    });
    app.useGlobalPipes(new ValidationPipe(validationOptions));
    app.useGlobalInterceptors(
      new ResolvePromisesInterceptor(),
      new ClassSerializerInterceptor(app.get(Reflector)),
    );

    const options = new DocumentBuilder()
      .setTitle('API')
      .setDescription('API docs')
      .setVersion('1.0')
      .addBearerAuth()
      .build();

    const document = SwaggerModule.createDocument(app, options);
    SwaggerModule.setup('docs', app, document);

    await app.init(); // Initialize the NestJS app
    const httpAdapter = app.getHttpAdapter().getInstance().use(expressApp);
    cachedServer = createServer(httpAdapter);

    logger.log('NestJS application initialized successfully.');
  } catch (error) {
    logger.error('Error during NestJS application initialization', error);
    throw new Error(`Bootstrap failure: ${error.message}`); // Rethrow to handle initialization errors
  }
}

export const handler: Handler = async (
  event: APIGatewayEvent,
  context: Context,
) => {
  logger.log('Lambda function invoked, before bootstrap');

  try {
    if (isColdStart) {
      logger.log('Cold start detected, bootstrapping the application...');
      await bootstrap();
      isColdStart = false;
    }

    logger.log('Application bootstrapped, handling event...');
    if (!cachedServer) {
      throw new Error(
        'Server not initialized. Ensure bootstrap has completed successfully.',
      );
    }

    return proxy(cachedServer, event, context, 'PROMISE').promise;
  } catch (error) {
    logger.error('Error handling Lambda event:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Internal Server Error',
        error: error.message,
      }),
    };
  }
};