import { app, clearCache, click, cloudronCli, goto, loginOIDC, sendKeys, setupBrowser, takeScreenshot, teardownBrowser, waitFor } from '@cloudron/charlie';

/* global it, describe, before, after, afterEach */

describe('Application life cycle test', function () {
    const ADMIN_USERNAME = 'admin';
    const ADMIN_PASSWORD = 'Changeme-123456';
    const PROJECT_NAME = 'charlie-project-' + Math.floor((Math.random() * 1000) + 1);

    before(setupBrowser);
    after(teardownBrowser);

    afterEach(async function () {
        await takeScreenshot(this.currentTest);
    });

    async function openLocalLoginForm() {
        await clearCache();
        await goto(`https://${app.fqdn}/login`, 'placeholder=Username');
    }

    async function openLocalLoginFormSso() {
        await clearCache();
        await goto(`https://${app.fqdn}/login`, 'More options');
        await click('More options');
        await waitFor('placeholder=Username');
    }

    async function submitLocalLogin(password) {
        await sendKeys('placeholder=Username', ADMIN_USERNAME);
        await sendKeys('placeholder=Password', password);
        await click('Login', { role: 'button' });
    }

    async function changeDefaultPassword() {
        await submitLocalLogin('admin');
        await waitFor('Update Password');
        await sendKeys('placeholder=Username', ADMIN_USERNAME);
        await sendKeys('placeholder=Current password', 'admin');
        await sendKeys('placeholder=New password', ADMIN_PASSWORD);
        await sendKeys('placeholder=Confirm new password', ADMIN_PASSWORD);
        await click('Change password', { role: 'button' });
        await waitFor('Sign In to your account');
    }

    async function login() {
        await submitLocalLogin(ADMIN_PASSWORD);
        await waitFor('Portfolio Vulnerabilities');
    }

    async function loginOidc() {
        await clearCache();
        const providerName = cloudronCli.getName();
        await goto(`https://${app.fqdn}/login`, providerName);
        await click(providerName);
        // new OIDC users have no team until an admin maps their Cloudron group
        await loginOIDC(/you don.t seem to have any permissions yet/);
    }

    async function createProject() {
        await goto(`https://${app.fqdn}/projects`, 'Create Project');
        await click('Create Project');
        await sendKeys('placeholder=Project Name', PROJECT_NAME);
        await click('Create', { role: 'button' });
        await waitFor(PROJECT_NAME);
    }

    async function checkProject() {
        await goto(`https://${app.fqdn}/projects`, PROJECT_NAME);
    }

    it('install app (sso)', cloudronCli.install);
    it('can change default admin password', async () => { await openLocalLoginFormSso(); await changeDefaultPassword(); });
    it('can login as admin', async () => { await openLocalLoginFormSso(); await login(); });
    it('can create project', createProject);
    it('can login via OIDC', loginOidc);

    it('restart app', cloudronCli.restart);
    it('can login as admin', async () => { await openLocalLoginFormSso(); await login(); });
    it('can check project', checkProject);

    it('backup app', cloudronCli.createBackup);
    it('restore app', cloudronCli.restoreFromLatestBackup);
    it('can login as admin', async () => { await openLocalLoginFormSso(); await login(); });
    it('can check project', checkProject);
    it('can login via OIDC', loginOidc);

    it('move to different location', cloudronCli.changeLocation);
    it('can login as admin', async () => { await openLocalLoginFormSso(); await login(); });
    it('can check project', checkProject);
    it('can login via OIDC', loginOidc);

    it('uninstall app', cloudronCli.uninstall);

    it('install app (no sso)', () => cloudronCli.install({ noSso: true }));
    it('can change default admin password', async () => { await openLocalLoginForm(); await changeDefaultPassword(); });
    it('can login as admin', async () => { await openLocalLoginForm(); await login(); });
    it('uninstall app', cloudronCli.uninstall);
});
