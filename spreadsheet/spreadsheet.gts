import { buildTask as _buildTask } from "ember-concurrency/-private/async-arrow-runtime";
import { eq, add, gt } from '@cardstack/boxel-ui/helpers';
import { CardDef, field, contains, Component } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import TextAreaField from 'https://cardstack.com/base/text-area';
import { Button } from '@cardstack/boxel-ui/components';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { restartableTask, timeout } from 'ember-concurrency';
import TableIcon from '@cardstack/boxel-icons/table';
import "./spreadsheet.gts.CiAgICAgIC5zcHJlYWRzaGVldC1jb250YWluZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgd2lkdGg6IDEwMCU7CiAgICAgICAgaGVpZ2h0OiAxMDB2aDsKICAgICAgICBkaXNwbGF5OiBmbGV4OwogICAgICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICAgICAgZm9udC1mYW1pbHk6CiAgICAgICAgICAnSW50ZXInLAogICAgICAgICAgLWFwcGxlLXN5c3RlbSwKICAgICAgICAgIHNhbnMtc2VyaWY7CiAgICAgICAgYmFja2dyb3VuZDogdmFyKC0tYmFja2dyb3VuZCwgI2ZhZmJmYyk7CiAgICAgIH0KCiAgICAgIC5zcHJlYWRzaGVldC1oZWFkZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgZGlzcGxheTogZmxleDsKICAgICAgICBqdXN0aWZ5LWNvbnRlbnQ6IHNwYWNlLWJldHdlZW47CiAgICAgICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgICAgICBwYWRkaW5nOiAxcmVtIDEuNXJlbTsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1jYXJkLCAjZmZmZmZmKTsKICAgICAgICBib3JkZXItYm90dG9tOiAxcHggc29saWQgdmFyKC0tYm9yZGVyLCAjZTVlN2ViKTsKICAgICAgICBmbGV4LXNocmluazogMDsKICAgICAgfQoKICAgICAgLnRpdGxlLXNlY3Rpb25bZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgZGlzcGxheTogZmxleDsKICAgICAgICBhbGlnbi1pdGVtczogY2VudGVyOwogICAgICAgIGdhcDogMXJlbTsKICAgICAgfQoKICAgICAgLnRpdGxlLXNlY3Rpb24gaDFbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgbWFyZ2luOiAwOwogICAgICAgIGZvbnQtc2l6ZTogMS4yNXJlbTsKICAgICAgICBmb250LXdlaWdodDogNjAwOwogICAgICAgIGNvbG9yOiB2YXIoLS1mb3JlZ3JvdW5kLCAjMTExODI3KTsKICAgICAgfQoKICAgICAgLnNhdmUtc3RhdHVzW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIHBhZGRpbmc6IDAuMjVyZW0gMC41cmVtOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuMzc1cmVtOwogICAgICAgIGZvbnQtc2l6ZTogMC43NXJlbTsKICAgICAgICBmb250LXdlaWdodDogNTAwOwogICAgICB9CgogICAgICAuc2F2ZS1zdGF0dXMuc3VjY2Vzc1tkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1zdWNjZXNzLCAjZGNmY2U3KTsKICAgICAgICBjb2xvcjogdmFyKC0tc3VjY2Vzcy1mb3JlZ3JvdW5kLCAjMTY2NTM0KTsKICAgICAgfQoKICAgICAgLnNhdmUtc3RhdHVzLnBlbmRpbmdbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgYmFja2dyb3VuZDogdmFyKC0td2FybmluZywgI2ZlZjNjNyk7CiAgICAgICAgY29sb3I6IHZhcigtLXdhcm5pbmctZm9yZWdyb3VuZCwgIzkyNDAwZSk7CiAgICAgIH0KCiAgICAgIC5kYXRhLXN0YXRzW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIHBhZGRpbmc6IDAuMjVyZW0gMC41cmVtOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuMzc1cmVtOwogICAgICAgIGZvbnQtc2l6ZTogMC43NXJlbTsKICAgICAgICBmb250LXdlaWdodDogNTAwOwogICAgICAgIGJhY2tncm91bmQ6ICNmM2Y0ZjY7CiAgICAgICAgY29sb3I6ICM2YjcyODA7CiAgICAgIH0KCiAgICAgIC50b29sYmFyW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIGRpc3BsYXk6IGZsZXg7CiAgICAgICAgZ2FwOiAwLjVyZW07CiAgICAgIH0KCiAgICAgIC5hZGQtYnV0dG9uW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIHBhZGRpbmc6IDAuNXJlbSAxcmVtOwogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLXByaW1hcnksICMzYjgyZjYpOwogICAgICAgIGNvbG9yOiB2YXIoLS1wcmltYXJ5LWZvcmVncm91bmQsICNmZmZmZmYpOwogICAgICAgIGJvcmRlcjogbm9uZTsKICAgICAgICBib3JkZXItcmFkaXVzOiAwLjM3NXJlbTsKICAgICAgICBmb250LXNpemU6IDAuODc1cmVtOwogICAgICAgIGZvbnQtd2VpZ2h0OiA1MDA7CiAgICAgICAgY3Vyc29yOiBwb2ludGVyOwogICAgICAgIHRyYW5zaXRpb246IGJhY2tncm91bmQtY29sb3IgMC4xNXM7CiAgICAgIH0KCiAgICAgIC5hZGQtYnV0dG9uW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl06aG92ZXIgewogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLXByaW1hcnktaG92ZXIsICMyNTYzZWIpOwogICAgICB9CgogICAgICAuZGVsaW1pdGVyLWZpZWxkW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIGRpc3BsYXk6IGlubGluZS1mbGV4OwogICAgICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICAgICAgZ2FwOiAwLjM3NXJlbTsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1tdXRlZCwgI2YzZjRmNik7CiAgICAgICAgcGFkZGluZzogMC4yNXJlbSAwLjVyZW07CiAgICAgICAgYm9yZGVyLXJhZGl1czogMC4zNzVyZW07CiAgICAgICAgcG9zaXRpb246IHJlbGF0aXZlOwogICAgICB9CgogICAgICAuZGVsaW1pdGVyLWxhYmVsW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIGZvbnQtc2l6ZTogMC43NXJlbTsKICAgICAgICBjb2xvcjogdmFyKC0tbXV0ZWQtZm9yZWdyb3VuZCwgIzZiNzI4MCk7CiAgICAgIH0KCiAgICAgIC5kZWxpbWl0ZXItaW5wdXRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgd2lkdGg6IDRyZW07CiAgICAgICAgcGFkZGluZzogMC4yNXJlbSAwLjVyZW07CiAgICAgICAgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYm9yZGVyLCAjZTVlN2ViKTsKICAgICAgICBib3JkZXItcmFkaXVzOiAwLjM3NXJlbTsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1jYXJkLCAjZmZmZmZmKTsKICAgICAgICBmb250LXNpemU6IDAuODEyNXJlbTsKICAgICAgfQoKICAgICAgLmltcG9ydC1sYWJlbFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBkaXNwbGF5OiBpbmxpbmUtZmxleDsKICAgICAgICBhbGlnbi1pdGVtczogY2VudGVyOwogICAgICAgIGdhcDogMC4zNzVyZW07CiAgICAgICAgcGFkZGluZzogMC41cmVtIDFyZW07CiAgICAgICAgYmFja2dyb3VuZDogdmFyKC0tc2Vjb25kYXJ5LCAjMTBiOTgxKTsKICAgICAgICBjb2xvcjogdmFyKC0tc2Vjb25kYXJ5LWZvcmVncm91bmQsICNmZmZmZmYpOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuMzc1cmVtOwogICAgICAgIGZvbnQtc2l6ZTogMC44NzVyZW07CiAgICAgICAgZm9udC13ZWlnaHQ6IDUwMDsKICAgICAgICBjdXJzb3I6IHBvaW50ZXI7CiAgICAgICAgdHJhbnNpdGlvbjogYmFja2dyb3VuZC1jb2xvciAwLjE1czsKICAgICAgfQoKICAgICAgLmltcG9ydC1sYWJlbFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdOmhvdmVyIHsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1zZWNvbmRhcnktaG92ZXIsICMwNTk2NjkpOwogICAgICB9CgogICAgICAuaGVscC1idXR0b25bZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgZGlzcGxheTogaW5saW5lLWZsZXg7CiAgICAgICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgICAgICBqdXN0aWZ5LWNvbnRlbnQ6IGNlbnRlcjsKICAgICAgICB3aWR0aDogMS41cmVtOwogICAgICAgIGhlaWdodDogMS41cmVtOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuMzc1cmVtOwogICAgICAgIGJvcmRlcjogMXB4IHNvbGlkIHZhcigtLWJvcmRlciwgI2U1ZTdlYik7CiAgICAgICAgYmFja2dyb3VuZDogdmFyKC0tY2FyZCwgI2ZmZmZmZik7CiAgICAgICAgY29sb3I6IHZhcigtLWZvcmVncm91bmQsICMzNzQxNTEpOwogICAgICAgIGZvbnQtd2VpZ2h0OiA2MDA7CiAgICAgICAgY3Vyc29yOiBwb2ludGVyOwogICAgICAgIHBvc2l0aW9uOiByZWxhdGl2ZTsKICAgICAgfQoKICAgICAgLmhlbHAtYnV0dG9uW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl06aG92ZXIgewogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLW11dGVkLCAjZjNmNGY2KTsKICAgICAgfQoKICAgICAgLmRlbGltaXRlci10b29sdGlwW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIHBvc2l0aW9uOiBhYnNvbHV0ZTsKICAgICAgICB0b3A6IGNhbGMoMTAwJSArIDAuNXJlbSk7CiAgICAgICAgcmlnaHQ6IDA7CiAgICAgICAgei1pbmRleDogMTAwMDsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1wb3BvdmVyLCAjZmZmZmZmKTsKICAgICAgICBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIsICNlNWU3ZWIpOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuNXJlbTsKICAgICAgICBib3gtc2hhZG93OiAwIDEwcHggMjVweCByZ2JhKDAsIDAsIDAsIDAuMSk7CiAgICAgICAgbWluLXdpZHRoOiAxNnJlbTsKICAgICAgICBhbmltYXRpb246IHRvb2x0aXBGYWRlSW4tZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiIDAuMnMgZWFzZS1vdXQ7CiAgICAgIH0KCiAgICAgIC5kZWxpbWl0ZXItdG9vbHRpcFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdOjpiZWZvcmUgewogICAgICAgIGNvbnRlbnQ6ICcnOwogICAgICAgIHBvc2l0aW9uOiBhYnNvbHV0ZTsKICAgICAgICB0b3A6IC0wLjVyZW07CiAgICAgICAgcmlnaHQ6IDAuNzVyZW07CiAgICAgICAgd2lkdGg6IDA7CiAgICAgICAgaGVpZ2h0OiAwOwogICAgICAgIGJvcmRlci1sZWZ0OiAwLjVyZW0gc29saWQgdHJhbnNwYXJlbnQ7CiAgICAgICAgYm9yZGVyLXJpZ2h0OiAwLjVyZW0gc29saWQgdHJhbnNwYXJlbnQ7CiAgICAgICAgYm9yZGVyLWJvdHRvbTogMC41cmVtIHNvbGlkIHZhcigtLWJvcmRlciwgI2U1ZTdlYik7CiAgICAgIH0KCiAgICAgIC5kZWxpbWl0ZXItdG9vbHRpcFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdOjphZnRlciB7CiAgICAgICAgY29udGVudDogJyc7CiAgICAgICAgcG9zaXRpb246IGFic29sdXRlOwogICAgICAgIHRvcDogLTAuNDM3NXJlbTsKICAgICAgICByaWdodDogMC44MTI1cmVtOwogICAgICAgIHdpZHRoOiAwOwogICAgICAgIGhlaWdodDogMDsKICAgICAgICBib3JkZXItbGVmdDogMC4zNzVyZW0gc29saWQgdHJhbnNwYXJlbnQ7CiAgICAgICAgYm9yZGVyLXJpZ2h0OiAwLjM3NXJlbSBzb2xpZCB0cmFuc3BhcmVudDsKICAgICAgICBib3JkZXItYm90dG9tOiAwLjM3NXJlbSBzb2xpZCB2YXIoLS1wb3BvdmVyLCAjZmZmZmZmKTsKICAgICAgfQoKICAgICAgLnRvb2x0aXAtY29udGVudFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBwYWRkaW5nOiAwLjc1cmVtOwogICAgICAgIHBvc2l0aW9uOiByZWxhdGl2ZTsKICAgICAgfQoKICAgICAgLmNsb3NlLWJ1dHRvbltkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBwb3NpdGlvbjogYWJzb2x1dGU7CiAgICAgICAgdG9wOiAwLjVyZW07CiAgICAgICAgcmlnaHQ6IDAuNXJlbTsKICAgICAgICB3aWR0aDogMS4yNXJlbTsKICAgICAgICBoZWlnaHQ6IDEuMjVyZW07CiAgICAgICAgYm9yZGVyOiBub25lOwogICAgICAgIGJhY2tncm91bmQ6IG5vbmU7CiAgICAgICAgY29sb3I6IHZhcigtLW11dGVkLWZvcmVncm91bmQsICM5Y2EzYWYpOwogICAgICAgIGN1cnNvcjogcG9pbnRlcjsKICAgICAgICBkaXNwbGF5OiBmbGV4OwogICAgICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICAgICAganVzdGlmeS1jb250ZW50OiBjZW50ZXI7CiAgICAgICAgYm9yZGVyLXJhZGl1czogMC4yNXJlbTsKICAgICAgICBmb250LXNpemU6IDFyZW07CiAgICAgICAgbGluZS1oZWlnaHQ6IDE7CiAgICAgIH0KCiAgICAgIC5jbG9zZS1idXR0b25bZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXTpob3ZlciB7CiAgICAgICAgYmFja2dyb3VuZDogdmFyKC0tbXV0ZWQsICNmM2Y0ZjYpOwogICAgICAgIGNvbG9yOiB2YXIoLS1mb3JlZ3JvdW5kLCAjMzc0MTUxKTsKICAgICAgfQoKICAgICAgLnRvb2x0aXAtaGVhZGVyW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIG1hcmdpbi1ib3R0b206IDAuNzVyZW07CiAgICAgICAgcGFkZGluZy1yaWdodDogMS41cmVtOwogICAgICAgIGZvbnQtc2l6ZTogMC44NzVyZW07CiAgICAgICAgY29sb3I6IHZhcigtLXBvcG92ZXItZm9yZWdyb3VuZCwgIzExMTgyNyk7CiAgICAgIH0KCiAgICAgIC5kZWxpbWl0ZXItb3B0aW9uc1tkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBkaXNwbGF5OiBmbGV4OwogICAgICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICAgICAgZ2FwOiAwLjVyZW07CiAgICAgICAgbWFyZ2luLWJvdHRvbTogMC43NXJlbTsKICAgICAgfQoKICAgICAgLmRlbGltaXRlci1yb3dbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgZGlzcGxheTogZ3JpZDsKICAgICAgICBncmlkLXRlbXBsYXRlLWNvbHVtbnM6IDEuNXJlbSAxZnIgMWZyOwogICAgICAgIGdhcDogMC41cmVtOwogICAgICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICAgICAgZm9udC1zaXplOiAwLjgxMjVyZW07CiAgICAgIH0KCiAgICAgIC5kZWxpbWl0ZXItcm93IGNvZGVbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgYmFja2dyb3VuZDogdmFyKC0tbXV0ZWQsICNmM2Y0ZjYpOwogICAgICAgIHBhZGRpbmc6IDAuMTI1cmVtIDAuMjVyZW07CiAgICAgICAgYm9yZGVyLXJhZGl1czogMC4yNXJlbTsKICAgICAgICBmb250LWZhbWlseTogJ1NGIE1vbm8nLCAnTW9uYWNvJywgJ0luY29uc29sYXRhJywgbW9ub3NwYWNlOwogICAgICAgIGZvbnQtc2l6ZTogMC43NXJlbTsKICAgICAgICBjb2xvcjogdmFyKC0tZm9yZWdyb3VuZCwgIzFmMjkzNyk7CiAgICAgIH0KCiAgICAgIC5kZWxpbWl0ZXItcm93IC5leGFtcGxlW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIGZvbnQtZmFtaWx5OiAnU0YgTW9ubycsICdNb25hY28nLCAnSW5jb25zb2xhdGEnLCBtb25vc3BhY2U7CiAgICAgICAgZm9udC1zaXplOiAwLjc1cmVtOwogICAgICAgIGNvbG9yOiB2YXIoLS1tdXRlZC1mb3JlZ3JvdW5kLCAjNmI3MjgwKTsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1iYWNrZ3JvdW5kLCAjZjlmYWZiKTsKICAgICAgICBwYWRkaW5nOiAwLjEyNXJlbSAwLjI1cmVtOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuMjVyZW07CiAgICAgIH0KCiAgICAgIC50b29sdGlwLXRpcFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBmb250LXNpemU6IDAuNzVyZW07CiAgICAgICAgY29sb3I6IHZhcigtLXByaW1hcnksICMzYjgyZjYpOwogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLXByaW1hcnktYmFja2dyb3VuZCwgI2VmZjZmZik7CiAgICAgICAgcGFkZGluZzogMC41cmVtOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuMjVyZW07CiAgICAgICAgYm9yZGVyLWxlZnQ6IDNweCBzb2xpZCB2YXIoLS1wcmltYXJ5LCAjM2I4MmY2KTsKICAgICAgfQoKICAgICAgQGtleWZyYW1lcyB0b29sdGlwRmFkZUluLWRhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYiB7CiAgICAgICAgZnJvbSB7CiAgICAgICAgICBvcGFjaXR5OiAwOwogICAgICAgICAgdHJhbnNmb3JtOiB0cmFuc2xhdGVZKC0wLjI1cmVtKTsKICAgICAgICB9CiAgICAgICAgdG8gewogICAgICAgICAgb3BhY2l0eTogMTsKICAgICAgICAgIHRyYW5zZm9ybTogdHJhbnNsYXRlWSgwKTsKICAgICAgICB9CiAgICAgIH0KCiAgICAgIC5maWxlLWlucHV0LWhpZGRlbltkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBkaXNwbGF5OiBub25lOwogICAgICB9CgogICAgICAudGFibGUtd3JhcHBlcltkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBmbGV4OiAxOwogICAgICAgIG92ZXJmbG93OiBhdXRvOwogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLWNhcmQsICNmZmZmZmYpOwogICAgICAgIG1hcmdpbjogMCAxLjVyZW0gMS41cmVtOwogICAgICAgIGJvcmRlci1yYWRpdXM6IDAuNXJlbTsKICAgICAgICBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIsICNlNWU3ZWIpOwogICAgICB9CgogICAgICAuc3ByZWFkc2hlZXQtdGFibGVbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgd2lkdGg6IDEwMCU7CiAgICAgICAgYm9yZGVyLWNvbGxhcHNlOiBzZXBhcmF0ZTsKICAgICAgICBib3JkZXItc3BhY2luZzogMDsKICAgICAgICBmb250LXNpemU6IDAuODc1cmVtOwogICAgICB9CgogICAgICAuaGVhZGVyLXJvd1tkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1tdXRlZCwgI2Y5ZmFmYik7CiAgICAgICAgcG9zaXRpb246IHN0aWNreTsKICAgICAgICB0b3A6IDA7CiAgICAgICAgei1pbmRleDogMTA7CiAgICAgIH0KCiAgICAgIC5yb3ctbnVtYmVyW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLW11dGVkLCAjZjNmNGY2KTsKICAgICAgICB3aWR0aDogNTBweDsKICAgICAgICB0ZXh0LWFsaWduOiBjZW50ZXI7CiAgICAgICAgZm9udC13ZWlnaHQ6IDYwMDsKICAgICAgICBjb2xvcjogdmFyKC0tbXV0ZWQtZm9yZWdyb3VuZCwgIzZiNzI4MCk7CiAgICAgICAgYm9yZGVyLWJvdHRvbTogMXB4IHNvbGlkIHZhcigtLWJvcmRlciwgI2U1ZTdlYik7CiAgICAgICAgYm9yZGVyLXJpZ2h0OiAxcHggc29saWQgdmFyKC0tYm9yZGVyLCAjZTVlN2ViKTsKICAgICAgICBwYWRkaW5nOiAwLjVyZW0gMC4yNXJlbTsKICAgICAgICBwb3NpdGlvbjogc3RpY2t5OwogICAgICAgIGxlZnQ6IDA7CiAgICAgICAgei1pbmRleDogNTsKICAgICAgfQoKICAgICAgLmNvbHVtbi1oZWFkZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgbWluLXdpZHRoOiAxMjBweDsKICAgICAgICBwYWRkaW5nOiAwLjVyZW07CiAgICAgICAgYm9yZGVyLWJvdHRvbTogMXB4IHNvbGlkIHZhcigtLWJvcmRlciwgI2U1ZTdlYik7CiAgICAgICAgYm9yZGVyLXJpZ2h0OiAxcHggc29saWQgdmFyKC0tYm9yZGVyLCAjZTVlN2ViKTsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1tdXRlZCwgI2Y5ZmFmYik7CiAgICAgIH0KCiAgICAgIC5oZWFkZXItaW5wdXRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgd2lkdGg6IDEwMCU7CiAgICAgICAgYm9yZGVyOiBub25lOwogICAgICAgIGJhY2tncm91bmQ6IHRyYW5zcGFyZW50OwogICAgICAgIGZvbnQtd2VpZ2h0OiA2MDA7CiAgICAgICAgY29sb3I6IHZhcigtLWZvcmVncm91bmQsICMzNzQxNTEpOwogICAgICAgIGZvbnQtc2l6ZTogMC44NzVyZW07CiAgICAgICAgcGFkZGluZzogMC4yNXJlbTsKICAgICAgfQoKICAgICAgLmhlYWRlci1pbnB1dFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdOmZvY3VzIHsKICAgICAgICBvdXRsaW5lOiAycHggc29saWQgdmFyKC0tcHJpbWFyeSwgIzNiODJmNik7CiAgICAgICAgb3V0bGluZS1vZmZzZXQ6IC0ycHg7CiAgICAgICAgYm9yZGVyLXJhZGl1czogMC4yNXJlbTsKICAgICAgfQoKICAgICAgLmhlYWRlci1kaXNwbGF5W2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIHdpZHRoOiAxMDAlOwogICAgICAgIGZvbnQtd2VpZ2h0OiA2MDA7CiAgICAgICAgY29sb3I6IHZhcigtLWZvcmVncm91bmQsICMzNzQxNTEpOwogICAgICAgIGZvbnQtc2l6ZTogMC44NzVyZW07CiAgICAgICAgcGFkZGluZzogMC4yNXJlbTsKICAgICAgICBjdXJzb3I6IHRleHQ7CiAgICAgICAgbWluLWhlaWdodDogMS41cmVtOwogICAgICAgIGRpc3BsYXk6IGZsZXg7CiAgICAgICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgICAgfQoKICAgICAgLmhlYWRlci1kaXNwbGF5W2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl06aG92ZXIgewogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLWFjY2VudCwgI2YzZjRmNik7CiAgICAgICAgYm9yZGVyLXJhZGl1czogMC4yNXJlbTsKICAgICAgfQoKICAgICAgLmRhdGEtcm93W2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl06bnRoLWNoaWxkKGV2ZW4pIHsKICAgICAgICBiYWNrZ3JvdW5kOiB2YXIoLS1tdXRlZCwgI2Y5ZmFmYik7CiAgICAgIH0KCiAgICAgIC5kYXRhLWNlbGxbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgbWluLXdpZHRoOiAxMjBweDsKICAgICAgICBib3JkZXItYm90dG9tOiAxcHggc29saWQgdmFyKC0tYm9yZGVyLCAjZTVlN2ViKTsKICAgICAgICBib3JkZXItcmlnaHQ6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIsICNlNWU3ZWIpOwogICAgICAgIHBhZGRpbmc6IDA7CiAgICAgICAgdmVydGljYWwtYWxpZ246IHRvcDsKICAgICAgfQoKICAgICAgLmNlbGwtZGlzcGxheVtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBwYWRkaW5nOiAwLjVyZW07CiAgICAgICAgbWluLWhlaWdodDogMi4yNXJlbTsKICAgICAgICBjdXJzb3I6IHRleHQ7CiAgICAgICAgZGlzcGxheTogZmxleDsKICAgICAgICBhbGlnbi1pdGVtczogY2VudGVyOwogICAgICAgIHdoaXRlLXNwYWNlOiBub3dyYXA7CiAgICAgICAgb3ZlcmZsb3c6IGhpZGRlbjsKICAgICAgICB0ZXh0LW92ZXJmbG93OiBlbGxpcHNpczsKICAgICAgICBtYXgtd2lkdGg6IDIwMHB4OwogICAgICB9CgogICAgICAuY2VsbC1kaXNwbGF5W2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl06aG92ZXIgewogICAgICAgIGJhY2tncm91bmQ6IHZhcigtLWFjY2VudCwgI2YzZjRmNik7CiAgICAgIH0KCiAgICAgIC5jZWxsLWlucHV0W2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIHdpZHRoOiAxMDAlOwogICAgICAgIGJvcmRlcjogbm9uZTsKICAgICAgICBwYWRkaW5nOiAwLjVyZW07CiAgICAgICAgZm9udC1zaXplOiAwLjg3NXJlbTsKICAgICAgICBtaW4taGVpZ2h0OiAyLjI1cmVtOwogICAgICAgIHJlc2l6ZTogbm9uZTsKICAgICAgICBvdXRsaW5lOiAycHggc29saWQgdmFyKC0tcHJpbWFyeSwgIzNiODJmNik7CiAgICAgICAgb3V0bGluZS1vZmZzZXQ6IC0ycHg7CiAgICAgIH0KCiAgICAgIC5zcHJlYWRzaGVldC1mb290ZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgcGFkZGluZzogMC43NXJlbSAxLjVyZW07CiAgICAgICAgYmFja2dyb3VuZDogdmFyKC0tY2FyZCwgI2ZmZmZmZik7CiAgICAgICAgYm9yZGVyLXRvcDogMXB4IHNvbGlkIHZhcigtLWJvcmRlciwgI2U1ZTdlYik7CiAgICAgICAgZmxleC1zaHJpbms6IDA7CiAgICAgIH0KCiAgICAgIC5maWxlLWluZm9bZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgZm9udC1zaXplOiAwLjg3NXJlbTsKICAgICAgICBjb2xvcjogdmFyKC0tbXV0ZWQtZm9yZWdyb3VuZCwgIzZiNzI4MCk7CiAgICAgIH0KCiAgICAgIC5lbXB0eS1zdGF0ZVtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICBkaXNwbGF5OiBmbGV4OwogICAgICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICAgICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgICAgICBqdXN0aWZ5LWNvbnRlbnQ6IGNlbnRlcjsKICAgICAgICBoZWlnaHQ6IDQwMHB4OwogICAgICAgIHRleHQtYWxpZ246IGNlbnRlcjsKICAgICAgICBjb2xvcjogdmFyKC0tbXV0ZWQtZm9yZWdyb3VuZCwgIzZiNzI4MCk7CiAgICAgIH0KCiAgICAgIC5lbXB0eS1pY29uW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIGZvbnQtc2l6ZTogM3JlbTsKICAgICAgICBtYXJnaW4tYm90dG9tOiAxcmVtOwogICAgICAgIG9wYWNpdHk6IDAuNzsKICAgICAgfQoKICAgICAgLmVtcHR5LXRpdGxlW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgIGZvbnQtc2l6ZTogMS4xMjVyZW07CiAgICAgICAgZm9udC13ZWlnaHQ6IDYwMDsKICAgICAgICBjb2xvcjogdmFyKC0tZm9yZWdyb3VuZCwgIzM3NDE1MSk7CiAgICAgICAgbWFyZ2luLWJvdHRvbTogMC41cmVtOwogICAgICB9CgogICAgICAuZW1wdHktZGVzY3JpcHRpb25bZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgZm9udC1zaXplOiAwLjg3NXJlbTsKICAgICAgICBtYXgtd2lkdGg6IDMwMHB4OwogICAgICAgIGxpbmUtaGVpZ2h0OiAxLjU7CiAgICAgIH0KCiAgICAgIC8qIFJlc3BvbnNpdmUgYWRqdXN0bWVudHMgKi8KICAgICAgQG1lZGlhIChtYXgtd2lkdGg6IDc2OHB4KSB7CiAgICAgICAgLnNwcmVhZHNoZWV0LWhlYWRlcltkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTA4MTlkMWY5MGJdIHsKICAgICAgICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICAgICAgICBnYXA6IDFyZW07CiAgICAgICAgICBhbGlnbi1pdGVtczogc3RyZXRjaDsKICAgICAgICB9CgogICAgICAgIC50b29sYmFyW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtMDgxOWQxZjkwYl0gewogICAgICAgICAganVzdGlmeS1jb250ZW50OiBzdHJldGNoOwogICAgICAgIH0KCiAgICAgICAgLmFkZC1idXR0b25bZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgICBmbGV4OiAxOwogICAgICAgIH0KCiAgICAgICAgLnRhYmxlLXdyYXBwZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi0wODE5ZDFmOTBiXSB7CiAgICAgICAgICBtYXJnaW46IDAgMC43NXJlbSAwLjc1cmVtOwogICAgICAgIH0KICAgICAgfQogICAg.glimmer-scoped.css";
import { setComponentTemplate } from "@ember/component";
import { createTemplateFactory } from "@ember/template-factory";
import "./spreadsheet.gts.CiAgICAgICAgLnNwcmVhZHNoZWV0LXByZXZpZXdbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi01ZWViMWQzNGYxXSB7CiAgICAgICAgICBwYWRkaW5nOiAxcmVtOwogICAgICAgICAgYmFja2dyb3VuZDogdmFyKC0tY2FyZCwgI2ZmZmZmZik7CiAgICAgICAgICBib3JkZXItcmFkaXVzOiAwLjVyZW07CiAgICAgICAgICBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIsICNlNWU3ZWIpOwogICAgICAgIH0KCiAgICAgICAgLnByZXZpZXctaGVhZGVyW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtNWVlYjFkMzRmMV0gewogICAgICAgICAgZGlzcGxheTogZmxleDsKICAgICAgICAgIGp1c3RpZnktY29udGVudDogc3BhY2UtYmV0d2VlbjsKICAgICAgICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICAgICAgICBtYXJnaW4tYm90dG9tOiAwLjc1cmVtOwogICAgICAgIH0KCiAgICAgICAgLnByZXZpZXctaGVhZGVyIGgzW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtNWVlYjFkMzRmMV0gewogICAgICAgICAgbWFyZ2luOiAwOwogICAgICAgICAgZm9udC1zaXplOiAxcmVtOwogICAgICAgICAgZm9udC13ZWlnaHQ6IDYwMDsKICAgICAgICAgIGNvbG9yOiB2YXIoLS1mb3JlZ3JvdW5kLCAjMTExODI3KTsKICAgICAgICB9CgogICAgICAgIC5maWxlbmFtZVtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTVlZWIxZDM0ZjFdIHsKICAgICAgICAgIGZvbnQtc2l6ZTogMC43NXJlbTsKICAgICAgICAgIGNvbG9yOiB2YXIoLS1tdXRlZC1mb3JlZ3JvdW5kLCAjNmI3MjgwKTsKICAgICAgICAgIGJhY2tncm91bmQ6IHZhcigtLW11dGVkLCAjZjNmNGY2KTsKICAgICAgICAgIHBhZGRpbmc6IDAuMjVyZW0gMC41cmVtOwogICAgICAgICAgYm9yZGVyLXJhZGl1czogMC4yNXJlbTsKICAgICAgICB9CgogICAgICAgIC5wcmV2aWV3LWNvbnRlbnRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi01ZWViMWQzNGYxXSB7CiAgICAgICAgICBjb2xvcjogdmFyKC0tbXV0ZWQtZm9yZWdyb3VuZCwgIzZiNzI4MCk7CiAgICAgICAgICBmb250LXNpemU6IDAuODc1cmVtOwogICAgICAgIH0KCiAgICAgICAgLmRhdGEtcHJldmlld1tkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTVlZWIxZDM0ZjFdIHsKICAgICAgICAgIGZvbnQtd2VpZ2h0OiA1MDA7CiAgICAgICAgfQoKICAgICAgICAuZW1wdHktcHJldmlld1tkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLTVlZWIxZDM0ZjFdIHsKICAgICAgICAgIGZvbnQtc3R5bGU6IGl0YWxpYzsKICAgICAgICB9CiAgICAgIA%3D%3D.glimmer-scoped.css";
import "./spreadsheet.gts.CiAgICAgICAgLmZpdHRlZC1jb250YWluZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSB7CiAgICAgICAgICB3aWR0aDogMTAwJTsKICAgICAgICAgIGhlaWdodDogMTAwJTsKICAgICAgICAgIGNvbnRhaW5lci10eXBlOiBzaXplOwogICAgICAgIH0KCiAgICAgICAgLmJhZGdlLWZvcm1hdFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLWEwZTlkMTc4NjldLAogICAgICAgIC5zdHJpcC1mb3JtYXRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSwKICAgICAgICAudGlsZS1mb3JtYXRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSwKICAgICAgICAuY2FyZC1mb3JtYXRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSB7CiAgICAgICAgICBkaXNwbGF5OiBub25lOwogICAgICAgICAgd2lkdGg6IDEwMCU7CiAgICAgICAgICBoZWlnaHQ6IDEwMCU7CiAgICAgICAgICBwYWRkaW5nOiBjbGFtcCgwLjE4NzVyZW0sIDIlLCAwLjYyNXJlbSk7CiAgICAgICAgICBib3gtc2l6aW5nOiBib3JkZXItYm94OwogICAgICAgIH0KCiAgICAgICAgQGNvbnRhaW5lciAobWF4LXdpZHRoOiAxNTBweCkgYW5kIChtYXgtaGVpZ2h0OiAxNjlweCkgewogICAgICAgICAgLmJhZGdlLWZvcm1hdFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLWEwZTlkMTc4NjldIHsKICAgICAgICAgICAgZGlzcGxheTogZmxleDsKICAgICAgICAgICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgICAgICAgICAgZ2FwOiAwLjVyZW07CiAgICAgICAgICB9CiAgICAgICAgfQoKICAgICAgICBAY29udGFpbmVyIChtaW4td2lkdGg6IDE1MXB4KSBhbmQgKG1heC1oZWlnaHQ6IDE2OXB4KSB7CiAgICAgICAgICAuc3RyaXAtZm9ybWF0W2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtYTBlOWQxNzg2OV0gewogICAgICAgICAgICBkaXNwbGF5OiBmbGV4OwogICAgICAgICAgICBhbGlnbi1pdGVtczogY2VudGVyOwogICAgICAgICAgICBnYXA6IDAuNzVyZW07CiAgICAgICAgICB9CiAgICAgICAgfQoKICAgICAgICBAY29udGFpbmVyIChtYXgtd2lkdGg6IDM5OXB4KSBhbmQgKG1pbi1oZWlnaHQ6IDE3MHB4KSB7CiAgICAgICAgICAudGlsZS1mb3JtYXRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSB7CiAgICAgICAgICAgIGRpc3BsYXk6IGZsZXg7CiAgICAgICAgICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICAgICAgICB9CiAgICAgICAgfQoKICAgICAgICBAY29udGFpbmVyIChtaW4td2lkdGg6IDQwMHB4KSBhbmQgKG1pbi1oZWlnaHQ6IDE3MHB4KSB7CiAgICAgICAgICAuY2FyZC1mb3JtYXRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSB7CiAgICAgICAgICAgIGRpc3BsYXk6IGZsZXg7CiAgICAgICAgICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICAgICAgICAgIGdhcDogMXJlbTsKICAgICAgICAgIH0KICAgICAgICB9CgogICAgICAgIC5zcHJlYWRzaGVldC1pY29uW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtYTBlOWQxNzg2OV0gewogICAgICAgICAgZm9udC1zaXplOiAxLjI1cmVtOwogICAgICAgICAgZmxleC1zaHJpbms6IDA7CiAgICAgICAgfQoKICAgICAgICAuc3ByZWFkc2hlZXQtaWNvbi5sYXJnZVtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLWEwZTlkMTc4NjldIHsKICAgICAgICAgIGZvbnQtc2l6ZTogMnJlbTsKICAgICAgICB9CgogICAgICAgIC5wcmltYXJ5LXRleHRbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSB7CiAgICAgICAgICBmb250LXNpemU6IDFlbTsKICAgICAgICAgIGZvbnQtd2VpZ2h0OiA2MDA7CiAgICAgICAgICBjb2xvcjogdmFyKC0tZm9yZWdyb3VuZCwgIzExMTgyNyk7CiAgICAgICAgICBsaW5lLWhlaWdodDogMS4yOwogICAgICAgIH0KCiAgICAgICAgLnNlY29uZGFyeS10ZXh0W2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtYTBlOWQxNzg2OV0gewogICAgICAgICAgZm9udC1zaXplOiAwLjg3NWVtOwogICAgICAgICAgZm9udC13ZWlnaHQ6IDUwMDsKICAgICAgICAgIGNvbG9yOiB2YXIoLS1tdXRlZC1mb3JlZ3JvdW5kLCAjNmI3MjgwKTsKICAgICAgICAgIGxpbmUtaGVpZ2h0OiAxLjM7CiAgICAgICAgfQoKICAgICAgICAudGVydGlhcnktdGV4dFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLWEwZTlkMTc4NjldIHsKICAgICAgICAgIGZvbnQtc2l6ZTogMC43NWVtOwogICAgICAgICAgZm9udC13ZWlnaHQ6IDQwMDsKICAgICAgICAgIGNvbG9yOiB2YXIoLS1tdXRlZC1mb3JlZ3JvdW5kLCAjOWNhM2FmKTsKICAgICAgICAgIGxpbmUtaGVpZ2h0OiAxLjQ7CiAgICAgICAgfQoKICAgICAgICAudGlsZS1oZWFkZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSB7CiAgICAgICAgICBkaXNwbGF5OiBmbGV4OwogICAgICAgICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgICAgICAgIGdhcDogMC43NXJlbTsKICAgICAgICAgIG1hcmdpbi1ib3R0b206IDAuNzVyZW07CiAgICAgICAgfQoKICAgICAgICAuY2FyZC1oZWFkZXJbZGF0YS1zY29wZWRjc3MtNDgyOGI3YWY5Zi1hMGU5ZDE3ODY5XSB7CiAgICAgICAgICBkaXNwbGF5OiBmbGV4OwogICAgICAgICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgICAgICAgIGdhcDogMXJlbTsKICAgICAgICB9CgogICAgICAgIC5oZWFkZXItdGV4dFtkYXRhLXNjb3BlZGNzcy00ODI4YjdhZjlmLWEwZTlkMTc4NjldIHsKICAgICAgICAgIGRpc3BsYXk6IGZsZXg7CiAgICAgICAgICBmbGV4LWRpcmVjdGlvbjogY29sdW1uOwogICAgICAgICAgZ2FwOiAwLjI1cmVtOwogICAgICAgIH0KCiAgICAgICAgLmNhcmQtZm9vdGVyW2RhdGEtc2NvcGVkY3NzLTQ4MjhiN2FmOWYtYTBlOWQxNzg2OV0gewogICAgICAgICAgbWFyZ2luLXRvcDogYXV0bzsKICAgICAgICAgIHBhZGRpbmctdG9wOiAwLjVyZW07CiAgICAgICAgICBib3JkZXItdG9wOiAxcHggc29saWQgdmFyKC0tYm9yZGVyLCAjZjNmNGY2KTsKICAgICAgICB9CiAgICAgIA%3D%3D.glimmer-scoped.css";
class SpreadsheetIsolated extends Component {
  static {
    dt7948.g(this.prototype, "parsedData", [tracked], function () {
      return [];
    });
  }
  #parsedData = (dt7948.i(this, "parsedData"), void 0);
  static {
    dt7948.g(this.prototype, "headers", [tracked], function () {
      return [];
    });
  }
  #headers = (dt7948.i(this, "headers"), void 0);
  static {
    dt7948.g(this.prototype, "hasUnsavedChanges", [tracked], function () {
      return false;
    });
  }
  #hasUnsavedChanges = (dt7948.i(this, "hasUnsavedChanges"), void 0);
  static {
    dt7948.g(this.prototype, "saveStatus", [tracked], function () {
      return '';
    });
  }
  #saveStatus = (dt7948.i(this, "saveStatus"), void 0);
  static {
    dt7948.g(this.prototype, "delimiter", [tracked], function () {
      return ',';
    });
  }
  #delimiter = (dt7948.i(this, "delimiter"), void 0);
  static {
    dt7948.g(this.prototype, "tempDelimiter", [tracked], function () {
      return '';
    });
  }
  #tempDelimiter = (dt7948.i(this, "tempDelimiter"), void 0);
  static {
    dt7948.g(this.prototype, "showDelimiterHelp", [tracked], function () {
      return false;
    });
  }
  #showDelimiterHelp = (dt7948.i(this, "showDelimiterHelp"), void 0);
  static {
    dt7948.g(this.prototype, "isEditingDelimiter", [tracked], function () {
      return false;
    });
  }
  #isEditingDelimiter = (dt7948.i(this, "isEditingDelimiter"), void 0);
  constructor(owner, args) {
    super(owner, args);
    this.delimiter = this.args.model?.delimiter || ',';
    this.initialParse.perform();
  }
  initialParse = _buildTask(() => ({
    context: this,
    generator: function* () {
      this.parseCSV();
      yield Promise.resolve();
    }
  }), null, "initialParse", "restartable");
  parseCSV() {
    try {
      const csvContent = this.args.model?.csvData || '';
      if (!csvContent.trim()) {
        this.headers = [];
        this.parsedData = [];
        return;
      }
      const lines = csvContent.trim().split('\n').filter(line => line.length > 0);
      if (lines.length === 0) {
        this.headers = ['Column A'];
        this.parsedData = [['']];
        return;
      }
      const newHeaders = this.parseCSVLine(lines[0]);
      if (newHeaders.length === 0) {
        this.headers = ['Column A'];
        this.parsedData = [['']];
        return;
      }
      const newData = lines.slice(1).map(line => this.parseCSVLine(line));
      const headerCount = newHeaders.length;
      const normalizedData = newData.map(row => {
        if (row.length === headerCount) return row;
        if (row.length > headerCount) return row.slice(0, headerCount);
        const padded = [...row];
        padded.length = headerCount;
        padded.fill('', row.length);
        return padded;
      });
      this.headers = newHeaders;
      this.parsedData = normalizedData;
      if (this.saveStatus && !this.hasUnsavedChanges) {
        this.saveStatus = '';
      }
    } catch (error) {
      console.error('Error parsing CSV:', error);
      this.headers = ['Column A'];
      this.parsedData = [['Error parsing CSV']];
    }
  }
  parseCSVLine(line) {
    if (!line || typeof line !== 'string') return [''];
    const result = [];
    let current = '';
    let inQuotes = false;
    try {
      for (let i = 0; i < line.length; i++) {
        const char = line[i];
        const nextChar = line[i + 1];
        if (char === '"' && !inQuotes) {
          inQuotes = true;
        } else if (char === '"' && inQuotes && nextChar === '"') {
          current += '"';
          i++;
        } else if (char === '"' && inQuotes) {
          inQuotes = false;
        } else if (char === this.delimiterChar && !inQuotes) {
          result.push(current);
          current = '';
        } else {
          current += char;
        }
      }
      result.push(current);
      return result;
    } catch (error) {
      console.warn('CSV line parsing error:', error, 'Line:', line);
      return [line];
    }
  }
  generateCSV() {
    const escapeCSVValue = value => {
      const safeValue = value?.toString() ?? '';
      if (safeValue.includes(this.delimiterChar) || safeValue.includes('"') || safeValue.includes('\n')) {
        return '"' + safeValue.replace(/"/g, '""') + '"';
      }
      return safeValue;
    };
    const headers = this.headers || [];
    const data = this.parsedData || [];
    if (headers.length === 0) {
      return '';
    }
    const headerRow = headers.map(escapeCSVValue).join(this.delimiterChar);
    const dataRows = data.map(row => row.map(escapeCSVValue).join(this.delimiterChar));
    return [headerRow, ...dataRows].join('\n');
  }
  autoSave = _buildTask(() => ({
    context: this,
    generator: function* () {
      if (!this.hasUnsavedChanges) return;
      this.saveStatus = 'Saving...';
      const csvContent = this.generateCSV();
      try {
        if (this.args.model) {
          this.args.model.csvData = csvContent;
        }
        yield timeout(500);
        this.hasUnsavedChanges = false;
        this.saveStatus = 'Saved ✓';
        yield timeout(2000);
        this.saveStatus = '';
      } catch (error) {
        console.error('Save error:', error);
        this.saveStatus = 'Save failed ✗';
        yield timeout(3000);
        this.saveStatus = '';
      }
    }
  }), null, "autoSave", "restartable");
  get delimiterChar() {
    const rawDelimiter = this.delimiter || this.args.model?.delimiter || ',';
    if (!rawDelimiter) return ',';
    const trimmed = rawDelimiter.trim();
    return trimmed === '\\t' ? '\t' : trimmed;
  }
  updateTempDelimiter = event => {
    this.tempDelimiter = event?.target?.value ?? '';
  };
  saveDelimiterEdit = () => {
    const normalized = this.tempDelimiter || ',';
    this.delimiter = normalized;
    if (this.args.model) {
      this.args.model.delimiter = normalized === '\t' ? '\\t' : normalized;
    }
    this.parseCSV();
    this.hasUnsavedChanges = true;
    this.autoSave.perform();
    this.isEditingDelimiter = false;
  };
  handleDelimiterKeydown = event => {
    if (event.key === 'Enter') {
      event.preventDefault();
      this.saveDelimiterEdit();
      event.target.blur();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      this.tempDelimiter = this.delimiter;
      this.isEditingDelimiter = false;
      event.target.blur();
    }
  };
  startDelimiterEdit = () => {
    this.tempDelimiter = this.delimiter;
    this.isEditingDelimiter = true;
  };
  toggleDelimiterHelp = () => {
    this.showDelimiterHelp = !this.showDelimiterHelp;
  };
  detectDelimiter = csvText => {
    if (!csvText.trim()) return ',';
    const firstLine = csvText.split('\n')[0] || '';
    const delimiters = [';', ',', '|', '\t'];
    const counts = delimiters.map(delim => ({
      delimiter: delim,
      count: firstLine.split(delim).length - 1
    }));
    const best = counts.reduce((prev, curr) => curr.count > prev.count ? curr : prev);
    return best.count > 0 ? best.delimiter : ',';
  };
  importFromFile = async event => {
    const input = event?.target;
    const file = input?.files?.[0];
    if (!file) return;
    if (file.size > 10 * 1024 * 1024) {
      console.error('File too large. Maximum size is 10MB.');
      return;
    }
    const validTypes = ['text/csv', 'application/csv', 'text/plain'];
    const validExtensions = ['.csv', '.txt'];
    const isValidType = validTypes.includes(file.type) || validExtensions.some(ext => file.name.toLowerCase().endsWith(ext));
    if (!isValidType) {
      console.warn('Unexpected file type. Expected CSV file, but will attempt to process.');
    }
    if (file.size === 0) {
      console.error('Cannot import empty file.');
      return;
    }
    try {
      const text = await file.text();
      const normalizedText = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
      const detectedDelimiter = this.detectDelimiter(normalizedText);
      if (this.args.model) {
        this.args.model.csvData = normalizedText;
        this.args.model.delimiter = detectedDelimiter === '\t' ? '\\t' : detectedDelimiter;
      }
      // Update the component's delimiter to match
      this.delimiter = detectedDelimiter;
      this.parseCSV();
      this.hasUnsavedChanges = true;
      this.autoSave.perform();
      if (input) input.value = '';
    } catch (e) {
      console.error('Import CSV failed', e);
    }
  };
  downloadCSV = () => {
    try {
      const csv = this.generateCSV();
      const base = this.args.model?.csvFilename?.trim() || this.args.model?.name?.trim() || 'spreadsheet';
      const filename = base.endsWith('.csv') ? base : `${base}.csv`;
      const blob = new Blob([csv], {
        type: 'text/csv;charset=utf-8;'
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      a.style.display = 'none';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error('Download CSV failed', e);
    }
  };
  static {
    setComponentTemplate(createTemplateFactory(
    /*
      
        <div class='spreadsheet-container'>
          <header class='spreadsheet-header'>
            <div class='title-section'>
              <h1>{{if @model.name @model.name 'Untitled Spreadsheet'}}</h1>
              {{#if this.saveStatus}}
                <span
                  class='save-status
                    {{if (eq this.saveStatus "Saved ✓") "success" "pending"}}'
                >
                  {{this.saveStatus}}
                </span>
              {{/if}}
            </div>
    
            <div class='toolbar'>
              <div class='delimiter-field'>
                <label
                  for='delimiter-input'
                  class='delimiter-label'
                  title='Delimiters: , ; | or \t (tab). Import/Export uses this. Quoted values keep embedded delimiters.'
                >Delimiter</label>
                <input
                  id='delimiter-input'
                  class='delimiter-input'
                  value={{if
                    this.isEditingDelimiter
                    this.tempDelimiter
                    this.delimiter
                  }}
                  placeholder=''
                  {{on 'focus' this.startDelimiterEdit}}
                  {{on 'input' this.updateTempDelimiter}}
                  {{on 'blur' this.saveDelimiterEdit}}
                  {{on 'keydown' this.handleDelimiterKeydown}}
                />
                <button
                  class='help-button'
                  title='Delimiter help'
                  {{on 'click' this.toggleDelimiterHelp}}
                >?</button>
                {{#if this.showDelimiterHelp}}
                  <div class='delimiter-tooltip'>
                    <div class='tooltip-content'>
                      <button
                        class='close-button'
                        {{on 'click' this.toggleDelimiterHelp}}
                      >×</button>
                      <div class='tooltip-header'>
                        <strong>Delimiter Options</strong>
                      </div>
                      <div class='delimiter-options'>
                        <div class='delimiter-row'>
                          <code>,</code>
                          <span>Comma</span>
                          <span class='example'>name,age</span>
                        </div>
                        <div class='delimiter-row'>
                          <code>;</code>
                          <span>Semicolon</span>
                          <span class='example'>name;age</span>
                        </div>
                        <div class='delimiter-row'>
                          <code>|</code>
                          <span>Pipe</span>
                          <span class='example'>name|age</span>
                        </div>
                        <div class='delimiter-row'>
                          <code>\t</code>
                          <span>Tab</span>
                          <span class='example'>
                            {{! template-lint-disable no-whitespace-for-layout }}
                            name&nbsp;&nbsp;&nbsp;&nbsp;age</span>
                        </div>
                      </div>
                      <div class='tooltip-tip'>
                        💡 Auto-detected on CSV import
                      </div>
                    </div>
                  </div>
                {{/if}}
              </div>
    
              <label class='import-label'>
                Import CSV
                <input
                  type='file'
                  accept='.csv,text/csv'
                  class='file-input-hidden'
                  {{on 'change' this.importFromFile}}
                />
              </label>
              <Button class='add-button' {{on 'click' this.downloadCSV}}>
                Download CSV
              </Button>
            </div>
          </header>
    
          <div class='table-wrapper'>
            {{#if (gt this.parsedData.length 0)}}
              <table class='spreadsheet-table'>
                <thead>
                  <tr class='header-row'>
                    <th class='row-number'>#</th>
                    {{#each this.headers as |header|}}
                      <th class='column-header'>
                        <div class='header-display'>
                          {{if header header 'Column Name'}}
                        </div>
                      </th>
                    {{/each}}
                  </tr>
                </thead>
    
                <tbody>
                  {{#each this.parsedData as |row rowIndex|}}
                    <tr class='data-row'>
                      <td class='row-number'>{{add rowIndex 1}}</td>
                      {{#each row as |cell|}}
                        <td class='data-cell'>
                          <div class='cell-display' title='{{cell}}'>
                            {{cell}}
                          </div>
                        </td>
                      {{/each}}
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            {{else}}
              <div class='empty-state'>
                <div class='empty-icon'>📄</div>
                <div class='empty-title'>No Data Yet</div>
                <div class='empty-description'>
                  Import a CSV file or paste data to get started
                </div>
              </div>
            {{/if}}
          </div>
    
          {{#if @model.csvFilename}}
            <footer class='spreadsheet-footer'>
              <span class='file-info'>
                Linked to:
                <strong>{{@model.csvFilename}}</strong>
              </span>
            </footer>
          {{/if}}
        </div>
    
        <style scoped>
          .spreadsheet-container {
            width: 100%;
            height: 100vh;
            display: flex;
            flex-direction: column;
            font-family:
              'Inter',
              -apple-system,
              sans-serif;
            background: var(--background, #fafbfc);
          }
    
          .spreadsheet-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 1rem 1.5rem;
            background: var(--card, #ffffff);
            border-bottom: 1px solid var(--border, #e5e7eb);
            flex-shrink: 0;
          }
    
          .title-section {
            display: flex;
            align-items: center;
            gap: 1rem;
          }
    
          .title-section h1 {
            margin: 0;
            font-size: 1.25rem;
            font-weight: 600;
            color: var(--foreground, #111827);
          }
    
          .save-status {
            padding: 0.25rem 0.5rem;
            border-radius: 0.375rem;
            font-size: 0.75rem;
            font-weight: 500;
          }
    
          .save-status.success {
            background: var(--success, #dcfce7);
            color: var(--success-foreground, #166534);
          }
    
          .save-status.pending {
            background: var(--warning, #fef3c7);
            color: var(--warning-foreground, #92400e);
          }
    
          .data-stats {
            padding: 0.25rem 0.5rem;
            border-radius: 0.375rem;
            font-size: 0.75rem;
            font-weight: 500;
            background: #f3f4f6;
            color: #6b7280;
          }
    
          .toolbar {
            display: flex;
            gap: 0.5rem;
          }
    
          .add-button {
            padding: 0.5rem 1rem;
            background: var(--primary, #3b82f6);
            color: var(--primary-foreground, #ffffff);
            border: none;
            border-radius: 0.375rem;
            font-size: 0.875rem;
            font-weight: 500;
            cursor: pointer;
            transition: background-color 0.15s;
          }
    
          .add-button:hover {
            background: var(--primary-hover, #2563eb);
          }
    
          .delimiter-field {
            display: inline-flex;
            align-items: center;
            gap: 0.375rem;
            background: var(--muted, #f3f4f6);
            padding: 0.25rem 0.5rem;
            border-radius: 0.375rem;
            position: relative;
          }
    
          .delimiter-label {
            font-size: 0.75rem;
            color: var(--muted-foreground, #6b7280);
          }
    
          .delimiter-input {
            width: 4rem;
            padding: 0.25rem 0.5rem;
            border: 1px solid var(--border, #e5e7eb);
            border-radius: 0.375rem;
            background: var(--card, #ffffff);
            font-size: 0.8125rem;
          }
    
          .import-label {
            display: inline-flex;
            align-items: center;
            gap: 0.375rem;
            padding: 0.5rem 1rem;
            background: var(--secondary, #10b981);
            color: var(--secondary-foreground, #ffffff);
            border-radius: 0.375rem;
            font-size: 0.875rem;
            font-weight: 500;
            cursor: pointer;
            transition: background-color 0.15s;
          }
    
          .import-label:hover {
            background: var(--secondary-hover, #059669);
          }
    
          .help-button {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 1.5rem;
            height: 1.5rem;
            border-radius: 0.375rem;
            border: 1px solid var(--border, #e5e7eb);
            background: var(--card, #ffffff);
            color: var(--foreground, #374151);
            font-weight: 600;
            cursor: pointer;
            position: relative;
          }
    
          .help-button:hover {
            background: var(--muted, #f3f4f6);
          }
    
          .delimiter-tooltip {
            position: absolute;
            top: calc(100% + 0.5rem);
            right: 0;
            z-index: 1000;
            background: var(--popover, #ffffff);
            border: 1px solid var(--border, #e5e7eb);
            border-radius: 0.5rem;
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.1);
            min-width: 16rem;
            animation: tooltipFadeIn 0.2s ease-out;
          }
    
          .delimiter-tooltip::before {
            content: '';
            position: absolute;
            top: -0.5rem;
            right: 0.75rem;
            width: 0;
            height: 0;
            border-left: 0.5rem solid transparent;
            border-right: 0.5rem solid transparent;
            border-bottom: 0.5rem solid var(--border, #e5e7eb);
          }
    
          .delimiter-tooltip::after {
            content: '';
            position: absolute;
            top: -0.4375rem;
            right: 0.8125rem;
            width: 0;
            height: 0;
            border-left: 0.375rem solid transparent;
            border-right: 0.375rem solid transparent;
            border-bottom: 0.375rem solid var(--popover, #ffffff);
          }
    
          .tooltip-content {
            padding: 0.75rem;
            position: relative;
          }
    
          .close-button {
            position: absolute;
            top: 0.5rem;
            right: 0.5rem;
            width: 1.25rem;
            height: 1.25rem;
            border: none;
            background: none;
            color: var(--muted-foreground, #9ca3af);
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 0.25rem;
            font-size: 1rem;
            line-height: 1;
          }
    
          .close-button:hover {
            background: var(--muted, #f3f4f6);
            color: var(--foreground, #374151);
          }
    
          .tooltip-header {
            margin-bottom: 0.75rem;
            padding-right: 1.5rem;
            font-size: 0.875rem;
            color: var(--popover-foreground, #111827);
          }
    
          .delimiter-options {
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
            margin-bottom: 0.75rem;
          }
    
          .delimiter-row {
            display: grid;
            grid-template-columns: 1.5rem 1fr 1fr;
            gap: 0.5rem;
            align-items: center;
            font-size: 0.8125rem;
          }
    
          .delimiter-row code {
            background: var(--muted, #f3f4f6);
            padding: 0.125rem 0.25rem;
            border-radius: 0.25rem;
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            font-size: 0.75rem;
            color: var(--foreground, #1f2937);
          }
    
          .delimiter-row .example {
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            font-size: 0.75rem;
            color: var(--muted-foreground, #6b7280);
            background: var(--background, #f9fafb);
            padding: 0.125rem 0.25rem;
            border-radius: 0.25rem;
          }
    
          .tooltip-tip {
            font-size: 0.75rem;
            color: var(--primary, #3b82f6);
            background: var(--primary-background, #eff6ff);
            padding: 0.5rem;
            border-radius: 0.25rem;
            border-left: 3px solid var(--primary, #3b82f6);
          }
    
          @keyframes tooltipFadeIn {
            from {
              opacity: 0;
              transform: translateY(-0.25rem);
            }
            to {
              opacity: 1;
              transform: translateY(0);
            }
          }
    
          .file-input-hidden {
            display: none;
          }
    
          .table-wrapper {
            flex: 1;
            overflow: auto;
            background: var(--card, #ffffff);
            margin: 0 1.5rem 1.5rem;
            border-radius: 0.5rem;
            border: 1px solid var(--border, #e5e7eb);
          }
    
          .spreadsheet-table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 0.875rem;
          }
    
          .header-row {
            background: var(--muted, #f9fafb);
            position: sticky;
            top: 0;
            z-index: 10;
          }
    
          .row-number {
            background: var(--muted, #f3f4f6);
            width: 50px;
            text-align: center;
            font-weight: 600;
            color: var(--muted-foreground, #6b7280);
            border-bottom: 1px solid var(--border, #e5e7eb);
            border-right: 1px solid var(--border, #e5e7eb);
            padding: 0.5rem 0.25rem;
            position: sticky;
            left: 0;
            z-index: 5;
          }
    
          .column-header {
            min-width: 120px;
            padding: 0.5rem;
            border-bottom: 1px solid var(--border, #e5e7eb);
            border-right: 1px solid var(--border, #e5e7eb);
            background: var(--muted, #f9fafb);
          }
    
          .header-input {
            width: 100%;
            border: none;
            background: transparent;
            font-weight: 600;
            color: var(--foreground, #374151);
            font-size: 0.875rem;
            padding: 0.25rem;
          }
    
          .header-input:focus {
            outline: 2px solid var(--primary, #3b82f6);
            outline-offset: -2px;
            border-radius: 0.25rem;
          }
    
          .header-display {
            width: 100%;
            font-weight: 600;
            color: var(--foreground, #374151);
            font-size: 0.875rem;
            padding: 0.25rem;
            cursor: text;
            min-height: 1.5rem;
            display: flex;
            align-items: center;
          }
    
          .header-display:hover {
            background: var(--accent, #f3f4f6);
            border-radius: 0.25rem;
          }
    
          .data-row:nth-child(even) {
            background: var(--muted, #f9fafb);
          }
    
          .data-cell {
            min-width: 120px;
            border-bottom: 1px solid var(--border, #e5e7eb);
            border-right: 1px solid var(--border, #e5e7eb);
            padding: 0;
            vertical-align: top;
          }
    
          .cell-display {
            padding: 0.5rem;
            min-height: 2.25rem;
            cursor: text;
            display: flex;
            align-items: center;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            max-width: 200px;
          }
    
          .cell-display:hover {
            background: var(--accent, #f3f4f6);
          }
    
          .cell-input {
            width: 100%;
            border: none;
            padding: 0.5rem;
            font-size: 0.875rem;
            min-height: 2.25rem;
            resize: none;
            outline: 2px solid var(--primary, #3b82f6);
            outline-offset: -2px;
          }
    
          .spreadsheet-footer {
            padding: 0.75rem 1.5rem;
            background: var(--card, #ffffff);
            border-top: 1px solid var(--border, #e5e7eb);
            flex-shrink: 0;
          }
    
          .file-info {
            font-size: 0.875rem;
            color: var(--muted-foreground, #6b7280);
          }
    
          .empty-state {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 400px;
            text-align: center;
            color: var(--muted-foreground, #6b7280);
          }
    
          .empty-icon {
            font-size: 3rem;
            margin-bottom: 1rem;
            opacity: 0.7;
          }
    
          .empty-title {
            font-size: 1.125rem;
            font-weight: 600;
            color: var(--foreground, #374151);
            margin-bottom: 0.5rem;
          }
    
          .empty-description {
            font-size: 0.875rem;
            max-width: 300px;
            line-height: 1.5;
          }
    
          /* Responsive adjustments *\/
          @media (max-width: 768px) {
            .spreadsheet-header {
              flex-direction: column;
              gap: 1rem;
              align-items: stretch;
            }
    
            .toolbar {
              justify-content: stretch;
            }
    
            .add-button {
              flex: 1;
            }
    
            .table-wrapper {
              margin: 0 0.75rem 0.75rem;
            }
          }
        </style>
      
    */
    {
      "id": "5epO5qdV",
      "block": "[[[1,\"\\n    \"],[10,0],[14,0,\"spreadsheet-container\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n      \"],[10,\"header\"],[14,0,\"spreadsheet-header\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n        \"],[10,0],[14,0,\"title-section\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n          \"],[10,\"h1\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,[52,[30,1,[\"name\"]],[30,1,[\"name\"]],\"Untitled Spreadsheet\"]],[13],[1,\"\\n\"],[41,[30,0,[\"saveStatus\"]],[[[1,\"            \"],[10,1],[15,0,[29,[\"save-status\\n                \",[52,[28,[32,0],[[30,0,[\"saveStatus\"]],\"Saved ✓\"],null],\"success\",\"pending\"]]]],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n              \"],[1,[30,0,[\"saveStatus\"]]],[1,\"\\n            \"],[13],[1,\"\\n\"]],[]],null],[1,\"        \"],[13],[1,\"\\n\\n        \"],[10,0],[14,0,\"toolbar\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n          \"],[10,0],[14,0,\"delimiter-field\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n            \"],[10,\"label\"],[14,\"for\",\"delimiter-input\"],[14,0,\"delimiter-label\"],[14,\"title\",\"Delimiters: , ; | or \\\\t (tab). Import/Export uses this. Quoted values keep embedded delimiters.\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"Delimiter\"],[13],[1,\"\\n            \"],[11,\"input\"],[24,1,\"delimiter-input\"],[24,0,\"delimiter-input\"],[16,2,[52,[30,0,[\"isEditingDelimiter\"]],[30,0,[\"tempDelimiter\"]],[30,0,[\"delimiter\"]]]],[24,\"placeholder\",\"\"],[24,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[4,[32,1],[\"focus\",[30,0,[\"startDelimiterEdit\"]]],null],[4,[32,1],[\"input\",[30,0,[\"updateTempDelimiter\"]]],null],[4,[32,1],[\"blur\",[30,0,[\"saveDelimiterEdit\"]]],null],[4,[32,1],[\"keydown\",[30,0,[\"handleDelimiterKeydown\"]]],null],[12],[13],[1,\"\\n            \"],[11,\"button\"],[24,0,\"help-button\"],[24,\"title\",\"Delimiter help\"],[24,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[4,[32,1],[\"click\",[30,0,[\"toggleDelimiterHelp\"]]],null],[12],[1,\"?\"],[13],[1,\"\\n\"],[41,[30,0,[\"showDelimiterHelp\"]],[[[1,\"              \"],[10,0],[14,0,\"delimiter-tooltip\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                \"],[10,0],[14,0,\"tooltip-content\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                  \"],[11,\"button\"],[24,0,\"close-button\"],[24,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[4,[32,1],[\"click\",[30,0,[\"toggleDelimiterHelp\"]]],null],[12],[1,\"×\"],[13],[1,\"\\n                  \"],[10,0],[14,0,\"tooltip-header\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                    \"],[10,\"strong\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"Delimiter Options\"],[13],[1,\"\\n                  \"],[13],[1,\"\\n                  \"],[10,0],[14,0,\"delimiter-options\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                    \"],[10,0],[14,0,\"delimiter-row\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                      \"],[10,\"code\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\",\"],[13],[1,\"\\n                      \"],[10,1],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"Comma\"],[13],[1,\"\\n                      \"],[10,1],[14,0,\"example\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"name,age\"],[13],[1,\"\\n                    \"],[13],[1,\"\\n                    \"],[10,0],[14,0,\"delimiter-row\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                      \"],[10,\"code\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\";\"],[13],[1,\"\\n                      \"],[10,1],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"Semicolon\"],[13],[1,\"\\n                      \"],[10,1],[14,0,\"example\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"name;age\"],[13],[1,\"\\n                    \"],[13],[1,\"\\n                    \"],[10,0],[14,0,\"delimiter-row\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                      \"],[10,\"code\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"|\"],[13],[1,\"\\n                      \"],[10,1],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"Pipe\"],[13],[1,\"\\n                      \"],[10,1],[14,0,\"example\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"name|age\"],[13],[1,\"\\n                    \"],[13],[1,\"\\n                    \"],[10,0],[14,0,\"delimiter-row\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                      \"],[10,\"code\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\\\t\"],[13],[1,\"\\n                      \"],[10,1],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"Tab\"],[13],[1,\"\\n                      \"],[10,1],[14,0,\"example\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n\"],[1,\"                        name    age\"],[13],[1,\"\\n                    \"],[13],[1,\"\\n                  \"],[13],[1,\"\\n                  \"],[10,0],[14,0,\"tooltip-tip\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                    💡 Auto-detected on CSV import\\n                  \"],[13],[1,\"\\n                \"],[13],[1,\"\\n              \"],[13],[1,\"\\n\"]],[]],null],[1,\"          \"],[13],[1,\"\\n\\n          \"],[10,\"label\"],[14,0,\"import-label\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n            Import CSV\\n            \"],[11,\"input\"],[24,\"accept\",\".csv,text/csv\"],[24,0,\"file-input-hidden\"],[24,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[24,4,\"file\"],[4,[32,1],[\"change\",[30,0,[\"importFromFile\"]]],null],[12],[13],[1,\"\\n          \"],[13],[1,\"\\n          \"],[8,[32,2],[[24,0,\"add-button\"],[24,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[4,[32,1],[\"click\",[30,0,[\"downloadCSV\"]]],null]],null,[[\"default\"],[[[[1,\"\\n            Download CSV\\n          \"]],[]]]]],[1,\"\\n        \"],[13],[1,\"\\n      \"],[13],[1,\"\\n\\n      \"],[10,0],[14,0,\"table-wrapper\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n\"],[41,[28,[32,3],[[30,0,[\"parsedData\",\"length\"]],0],null],[[[1,\"          \"],[10,\"table\"],[14,0,\"spreadsheet-table\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n            \"],[10,\"thead\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n              \"],[10,\"tr\"],[14,0,\"header-row\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                \"],[10,\"th\"],[14,0,\"row-number\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"#\"],[13],[1,\"\\n\"],[42,[28,[31,2],[[28,[31,2],[[30,0,[\"headers\"]]],null]],null],null,[[[1,\"                  \"],[10,\"th\"],[14,0,\"column-header\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                    \"],[10,0],[14,0,\"header-display\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                      \"],[1,[52,[30,2],[30,2],\"Column Name\"]],[1,\"\\n                    \"],[13],[1,\"\\n                  \"],[13],[1,\"\\n\"]],[2]],null],[1,\"              \"],[13],[1,\"\\n            \"],[13],[1,\"\\n\\n            \"],[10,\"tbody\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n\"],[42,[28,[31,2],[[28,[31,2],[[30,0,[\"parsedData\"]]],null]],null],null,[[[1,\"                \"],[10,\"tr\"],[14,0,\"data-row\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                  \"],[10,\"td\"],[14,0,\"row-number\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,[28,[32,4],[[30,4],1],null]],[13],[1,\"\\n\"],[42,[28,[31,2],[[28,[31,2],[[30,3]],null]],null],null,[[[1,\"                    \"],[10,\"td\"],[14,0,\"data-cell\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                      \"],[10,0],[14,0,\"cell-display\"],[15,\"title\",[29,[[30,5]]]],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n                        \"],[1,[30,5]],[1,\"\\n                      \"],[13],[1,\"\\n                    \"],[13],[1,\"\\n\"]],[5]],null],[1,\"                \"],[13],[1,\"\\n\"]],[3,4]],null],[1,\"            \"],[13],[1,\"\\n          \"],[13],[1,\"\\n\"]],[]],[[[1,\"          \"],[10,0],[14,0,\"empty-state\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n            \"],[10,0],[14,0,\"empty-icon\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"📄\"],[13],[1,\"\\n            \"],[10,0],[14,0,\"empty-title\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"No Data Yet\"],[13],[1,\"\\n            \"],[10,0],[14,0,\"empty-description\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n              Import a CSV file or paste data to get started\\n            \"],[13],[1,\"\\n          \"],[13],[1,\"\\n\"]],[]]],[1,\"      \"],[13],[1,\"\\n\\n\"],[41,[30,1,[\"csvFilename\"]],[[[1,\"        \"],[10,\"footer\"],[14,0,\"spreadsheet-footer\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n          \"],[10,1],[14,0,\"file-info\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,\"\\n            Linked to:\\n            \"],[10,\"strong\"],[14,\"data-scopedcss-4828b7af9f-0819d1f90b\",\"\"],[12],[1,[30,1,[\"csvFilename\"]]],[13],[1,\"\\n          \"],[13],[1,\"\\n        \"],[13],[1,\"\\n\"]],[]],null],[1,\"    \"],[13],[1,\"\\n\\n    \"],[1,\"\\n  \"]],[\"@model\",\"header\",\"row\",\"rowIndex\",\"cell\"],false,[\"if\",\"each\",\"-track-array\"]]",
      "moduleName": "/Users/richardtan/Desktop/boxel/packages/realm-server/spreadsheet/spreadsheet.gts",
      "scope": () => [eq, on, Button, gt, add],
      "isStrictMode": true
    }), this);
  }
}
export class Spreadsheet extends CardDef {
  static displayName = 'Spreadsheet';
  static icon = TableIcon;
  static {
    dt7948.g(this.prototype, "name", [field], function () {
      return contains(StringField);
    });
  }
  #name = (dt7948.i(this, "name"), void 0);
  static {
    dt7948.g(this.prototype, "csvData", [field], function () {
      return contains(TextAreaField);
    });
  }
  #csvData = (dt7948.i(this, "csvData"), void 0);
  static {
    dt7948.g(this.prototype, "csvFilename", [field], function () {
      return contains(StringField);
    });
  }
  #csvFilename = (dt7948.i(this, "csvFilename"), void 0);
  static {
    dt7948.g(this.prototype, "delimiter", [field], function () {
      return contains(StringField);
    });
  }
  #delimiter = (dt7948.i(this, "delimiter"), void 0);
  static {
    dt7948.g(this.prototype, "title", [field], function () {
      return contains(StringField, {
        computeVia: function () {
          return this.name ?? 'Untitled Spreadsheet';
        }
      });
    });
  }
  #title = (dt7948.i(this, "title"), void 0);
  static isolated = SpreadsheetIsolated;
  static embedded = class Embedded extends Component {
    get rowCount() {
      if (!this.args.model?.csvData) return 0;
      return this.args.model.csvData.split('\n').length - 1;
    }
    get columnCount() {
      if (!this.args.model?.csvData) return 0;
      const firstLine = this.args.model.csvData.split('\n')[0];
      const delim = this.args.model?.delimiter === '\\t' ? '\t' : this.args.model?.delimiter || ',';
      return firstLine ? firstLine.split(delim).length : 0;
    }
    static {
      setComponentTemplate(createTemplateFactory(
      /*
        
            <div class='spreadsheet-preview'>
              <div class='preview-header'>
                <h3>{{if @model.name @model.name 'Untitled Spreadsheet'}}</h3>
                {{#if @model.csvFilename}}
                  <span class='filename'>{{@model.csvFilename}}</span>
                {{/if}}
              </div>
      
              <div class='preview-content'>
                {{#if @model.csvData}}
                  <div class='data-preview'>
                    📊
                    {{this.rowCount}}
                    rows ×
                    {{this.columnCount}}
                    columns
                  </div>
                {{else}}
                  <div class='empty-preview'>
                    📝 Empty spreadsheet - click to start editing
                  </div>
                {{/if}}
              </div>
            </div>
      
            <style scoped>
              .spreadsheet-preview {
                padding: 1rem;
                background: var(--card, #ffffff);
                border-radius: 0.5rem;
                border: 1px solid var(--border, #e5e7eb);
              }
      
              .preview-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 0.75rem;
              }
      
              .preview-header h3 {
                margin: 0;
                font-size: 1rem;
                font-weight: 600;
                color: var(--foreground, #111827);
              }
      
              .filename {
                font-size: 0.75rem;
                color: var(--muted-foreground, #6b7280);
                background: var(--muted, #f3f4f6);
                padding: 0.25rem 0.5rem;
                border-radius: 0.25rem;
              }
      
              .preview-content {
                color: var(--muted-foreground, #6b7280);
                font-size: 0.875rem;
              }
      
              .data-preview {
                font-weight: 500;
              }
      
              .empty-preview {
                font-style: italic;
              }
            </style>
          
      */
      {
        "id": "r1r8RG7R",
        "block": "[[[1,\"\\n      \"],[10,0],[14,0,\"spreadsheet-preview\"],[14,\"data-scopedcss-4828b7af9f-5eeb1d34f1\",\"\"],[12],[1,\"\\n        \"],[10,0],[14,0,\"preview-header\"],[14,\"data-scopedcss-4828b7af9f-5eeb1d34f1\",\"\"],[12],[1,\"\\n          \"],[10,\"h3\"],[14,\"data-scopedcss-4828b7af9f-5eeb1d34f1\",\"\"],[12],[1,[52,[30,1,[\"name\"]],[30,1,[\"name\"]],\"Untitled Spreadsheet\"]],[13],[1,\"\\n\"],[41,[30,1,[\"csvFilename\"]],[[[1,\"            \"],[10,1],[14,0,\"filename\"],[14,\"data-scopedcss-4828b7af9f-5eeb1d34f1\",\"\"],[12],[1,[30,1,[\"csvFilename\"]]],[13],[1,\"\\n\"]],[]],null],[1,\"        \"],[13],[1,\"\\n\\n        \"],[10,0],[14,0,\"preview-content\"],[14,\"data-scopedcss-4828b7af9f-5eeb1d34f1\",\"\"],[12],[1,\"\\n\"],[41,[30,1,[\"csvData\"]],[[[1,\"            \"],[10,0],[14,0,\"data-preview\"],[14,\"data-scopedcss-4828b7af9f-5eeb1d34f1\",\"\"],[12],[1,\"\\n              📊\\n              \"],[1,[30,0,[\"rowCount\"]]],[1,\"\\n              rows ×\\n              \"],[1,[30,0,[\"columnCount\"]]],[1,\"\\n              columns\\n            \"],[13],[1,\"\\n\"]],[]],[[[1,\"            \"],[10,0],[14,0,\"empty-preview\"],[14,\"data-scopedcss-4828b7af9f-5eeb1d34f1\",\"\"],[12],[1,\"\\n              📝 Empty spreadsheet - click to start editing\\n            \"],[13],[1,\"\\n\"]],[]]],[1,\"        \"],[13],[1,\"\\n      \"],[13],[1,\"\\n\\n      \"],[1,\"\\n    \"]],[\"@model\"],false,[\"if\"]]",
        "moduleName": "/Users/richardtan/Desktop/boxel/packages/realm-server/spreadsheet/spreadsheet.gts",
        "isStrictMode": true
      }), this);
    }
  };
  static fitted = class Fitted extends Component {
    static {
      setComponentTemplate(createTemplateFactory(
      /*
        
            <div class='fitted-container'>
              <div class='fitted-format badge-format'>
                <div class='spreadsheet-icon'>📊</div>
                <div class='spreadsheet-info'>
                  <div class='primary-text'>{{if
                      @model.name
                      @model.name
                      'Spreadsheet'
                    }}</div>
                  <div class='secondary-text'>{{this.dataInfo}}</div>
                </div>
              </div>
      
              <div class='fitted-format strip-format'>
                <div class='spreadsheet-icon'>📊</div>
                <div class='spreadsheet-details'>
                  <div class='primary-text'>{{if
                      @model.name
                      @model.name
                      'Untitled Spreadsheet'
                    }}</div>
                  <div class='secondary-text'>{{this.dataInfo}}</div>
                  {{#if @model.csvFilename}}
                    <div class='tertiary-text'>{{@model.csvFilename}}</div>
                  {{/if}}
                </div>
              </div>
      
              <div class='fitted-format tile-format'>
                <div class='tile-header'>
                  <div class='spreadsheet-icon large'>📊</div>
                  <div class='primary-text'>{{if
                      @model.name
                      @model.name
                      'Untitled Spreadsheet'
                    }}</div>
                </div>
                <div class='tile-content'>
                  <div class='secondary-text'>{{this.dataInfo}}</div>
                  {{#if @model.csvFilename}}
                    <div class='tertiary-text'>Linked: {{@model.csvFilename}}</div>
                  {{/if}}
                </div>
              </div>
      
              <div class='fitted-format card-format'>
                <div class='card-header'>
                  <div class='spreadsheet-icon large'>📊</div>
                  <div class='header-text'>
                    <div class='primary-text'>{{if
                        @model.name
                        @model.name
                        'Untitled Spreadsheet'
                      }}</div>
                    <div class='secondary-text'>{{this.dataInfo}}</div>
                  </div>
                </div>
                {{#if @model.csvFilename}}
                  <div class='card-footer'>
                    <div class='tertiary-text'>File: {{@model.csvFilename}}</div>
                  </div>
                {{/if}}
              </div>
            </div>
      
            <style scoped>
              .fitted-container {
                width: 100%;
                height: 100%;
                container-type: size;
              }
      
              .badge-format,
              .strip-format,
              .tile-format,
              .card-format {
                display: none;
                width: 100%;
                height: 100%;
                padding: clamp(0.1875rem, 2%, 0.625rem);
                box-sizing: border-box;
              }
      
              @container (max-width: 150px) and (max-height: 169px) {
                .badge-format {
                  display: flex;
                  align-items: center;
                  gap: 0.5rem;
                }
              }
      
              @container (min-width: 151px) and (max-height: 169px) {
                .strip-format {
                  display: flex;
                  align-items: center;
                  gap: 0.75rem;
                }
              }
      
              @container (max-width: 399px) and (min-height: 170px) {
                .tile-format {
                  display: flex;
                  flex-direction: column;
                }
              }
      
              @container (min-width: 400px) and (min-height: 170px) {
                .card-format {
                  display: flex;
                  flex-direction: column;
                  gap: 1rem;
                }
              }
      
              .spreadsheet-icon {
                font-size: 1.25rem;
                flex-shrink: 0;
              }
      
              .spreadsheet-icon.large {
                font-size: 2rem;
              }
      
              .primary-text {
                font-size: 1em;
                font-weight: 600;
                color: var(--foreground, #111827);
                line-height: 1.2;
              }
      
              .secondary-text {
                font-size: 0.875em;
                font-weight: 500;
                color: var(--muted-foreground, #6b7280);
                line-height: 1.3;
              }
      
              .tertiary-text {
                font-size: 0.75em;
                font-weight: 400;
                color: var(--muted-foreground, #9ca3af);
                line-height: 1.4;
              }
      
              .tile-header {
                display: flex;
                align-items: center;
                gap: 0.75rem;
                margin-bottom: 0.75rem;
              }
      
              .card-header {
                display: flex;
                align-items: center;
                gap: 1rem;
              }
      
              .header-text {
                display: flex;
                flex-direction: column;
                gap: 0.25rem;
              }
      
              .card-footer {
                margin-top: auto;
                padding-top: 0.5rem;
                border-top: 1px solid var(--border, #f3f4f6);
              }
            </style>
          
      */
      {
        "id": "XPmBqww0",
        "block": "[[[1,\"\\n      \"],[10,0],[14,0,\"fitted-container\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n        \"],[10,0],[14,0,\"fitted-format badge-format\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n          \"],[10,0],[14,0,\"spreadsheet-icon\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"📊\"],[13],[1,\"\\n          \"],[10,0],[14,0,\"spreadsheet-info\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n            \"],[10,0],[14,0,\"primary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[52,[30,1,[\"name\"]],[30,1,[\"name\"]],\"Spreadsheet\"]],[13],[1,\"\\n            \"],[10,0],[14,0,\"secondary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[30,0,[\"dataInfo\"]]],[13],[1,\"\\n          \"],[13],[1,\"\\n        \"],[13],[1,\"\\n\\n        \"],[10,0],[14,0,\"fitted-format strip-format\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n          \"],[10,0],[14,0,\"spreadsheet-icon\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"📊\"],[13],[1,\"\\n          \"],[10,0],[14,0,\"spreadsheet-details\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n            \"],[10,0],[14,0,\"primary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[52,[30,1,[\"name\"]],[30,1,[\"name\"]],\"Untitled Spreadsheet\"]],[13],[1,\"\\n            \"],[10,0],[14,0,\"secondary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[30,0,[\"dataInfo\"]]],[13],[1,\"\\n\"],[41,[30,1,[\"csvFilename\"]],[[[1,\"              \"],[10,0],[14,0,\"tertiary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[30,1,[\"csvFilename\"]]],[13],[1,\"\\n\"]],[]],null],[1,\"          \"],[13],[1,\"\\n        \"],[13],[1,\"\\n\\n        \"],[10,0],[14,0,\"fitted-format tile-format\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n          \"],[10,0],[14,0,\"tile-header\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n            \"],[10,0],[14,0,\"spreadsheet-icon large\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"📊\"],[13],[1,\"\\n            \"],[10,0],[14,0,\"primary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[52,[30,1,[\"name\"]],[30,1,[\"name\"]],\"Untitled Spreadsheet\"]],[13],[1,\"\\n          \"],[13],[1,\"\\n          \"],[10,0],[14,0,\"tile-content\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n            \"],[10,0],[14,0,\"secondary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[30,0,[\"dataInfo\"]]],[13],[1,\"\\n\"],[41,[30,1,[\"csvFilename\"]],[[[1,\"              \"],[10,0],[14,0,\"tertiary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"Linked: \"],[1,[30,1,[\"csvFilename\"]]],[13],[1,\"\\n\"]],[]],null],[1,\"          \"],[13],[1,\"\\n        \"],[13],[1,\"\\n\\n        \"],[10,0],[14,0,\"fitted-format card-format\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n          \"],[10,0],[14,0,\"card-header\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n            \"],[10,0],[14,0,\"spreadsheet-icon large\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"📊\"],[13],[1,\"\\n            \"],[10,0],[14,0,\"header-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n              \"],[10,0],[14,0,\"primary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[52,[30,1,[\"name\"]],[30,1,[\"name\"]],\"Untitled Spreadsheet\"]],[13],[1,\"\\n              \"],[10,0],[14,0,\"secondary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,[30,0,[\"dataInfo\"]]],[13],[1,\"\\n            \"],[13],[1,\"\\n          \"],[13],[1,\"\\n\"],[41,[30,1,[\"csvFilename\"]],[[[1,\"            \"],[10,0],[14,0,\"card-footer\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"\\n              \"],[10,0],[14,0,\"tertiary-text\"],[14,\"data-scopedcss-4828b7af9f-a0e9d17869\",\"\"],[12],[1,\"File: \"],[1,[30,1,[\"csvFilename\"]]],[13],[1,\"\\n            \"],[13],[1,\"\\n\"]],[]],null],[1,\"        \"],[13],[1,\"\\n      \"],[13],[1,\"\\n\\n      \"],[1,\"\\n    \"]],[\"@model\"],false,[\"if\"]]",
        "moduleName": "/Users/richardtan/Desktop/boxel/packages/realm-server/spreadsheet/spreadsheet.gts",
        "isStrictMode": true
      }), this);
    }
    get dataInfo() {
      if (!this.args.model?.csvData) return 'Empty spreadsheet';
      const delim = this.args.model?.delimiter === '\\t' ? '\t' : this.args.model?.delimiter || ',';
      const lines = this.args.model.csvData.split('\n');
      const rows = Math.max(0, lines.length - 1);
      const cols = lines[0] ? lines[0].split(delim).length : 0;
      return `${rows} rows × ${cols} cols`;
    }
  };
}