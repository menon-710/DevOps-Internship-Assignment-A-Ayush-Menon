import { registerWorker, Logger } from 'iii-sdk';

const worker = registerWorker(process.env.III_URL ?? 'ws://localhost:49134');
const logger = new Logger();

worker.registerFunction(
  'math::add_two_numbers',
  async (payload: { a: number; b: number }) => {
    logger.info('math::add_two_numbers called in TypeScript', payload);
    const result = await worker.trigger({
      function_id: 'math::add',
      payload,
    });
    return {
      ...result,
      success: "You've connected two workers and they're interoperating seamlessly.",
    };
  },
);

console.log('Caller worker started - listening for calls');
// WebSocket keeps the process alive — no explicit blocking call needed
