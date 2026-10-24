#!/usr/bin/env python3

# DT keeps the SMTP password as an encrypted secret start.sh cannot write, so DT sends here without auth and this adds it

import asyncio
import os
import smtplib

from aiosmtpd.controller import Controller


class RelayHandler:
    async def handle_DATA(self, server, session, envelope):
        try:
            await asyncio.to_thread(self.forward, envelope)
        except (smtplib.SMTPException, OSError) as e:
            print(f"relay failed: {e}", flush=True)
            return "451 Relay failed"

        return "250 OK"

    def forward(self, envelope):
        with smtplib.SMTP(os.environ["CLOUDRON_MAIL_SMTP_SERVER"], int(os.environ["CLOUDRON_MAIL_SMTP_PORT"]), timeout=30) as smtp:
            smtp.login(os.environ["CLOUDRON_MAIL_SMTP_USERNAME"], os.environ["CLOUDRON_MAIL_SMTP_PASSWORD"])
            smtp.sendmail(os.environ["CLOUDRON_MAIL_FROM"], envelope.rcpt_tos, envelope.content)


async def main():
    controller = Controller(RelayHandler(), hostname="127.0.0.1", port=2525)
    controller.start()
    await asyncio.Event().wait()


asyncio.run(main())
