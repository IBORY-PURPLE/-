/**
 * parseKto · splitCode 단위 테스트 — 상류 호출 0.
 *
 * TSD §4-4 「파서가 조용히 깨지는 지점」 3분기((b) 평면 JSON · (c) resultCode≠0000 · (d) items "")
 * + 한도 초과 XML((a) quota) + 세종 36110 특례. 회귀 #1·#2·#3·#6 의 서버 절반.
 * 픽스처는 2026-09-14 실호출에서 본 형태(worker/README.md · Docs/개발일지.md)를 옮긴 것.
 *
 * 실행: npm test  (vitest run · environment node — 순수 함수라 workers 풀 불필요)
 */
import { describe, expect, it } from 'vitest';
import { parseKto, splitCode, type Parsed } from '../src/kto';

const XML_LIMIT =
  '<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>SERVICE ERROR</errMsg><returnAuthMsg>LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR</returnAuthMsg><returnReasonCode>22</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>';
const XML_KEY =
  '<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>SERVICE ERROR</errMsg><returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg><returnReasonCode>30</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>';

const OK_HEADER = { resultCode: '0000', resultMsg: 'OK' };
const wrap = (header: Record<string, unknown>, body?: Record<string, unknown>) => JSON.stringify({ response: { header, body } });

function asErr(r: Parsed) {
  if (r.ok) throw new Error('expected ok:false');
  return r;
}
function asOk(r: Parsed) {
  if (!r.ok) throw new Error(`expected ok:true, got ${r.kind} ${r.code}`);
  return r;
}

describe('parseKto (a) HTTP 비정상 · XML 본문', () => {
  it('① LIMITED_NUMBER XML → quota · code 22 (HTTP 200 이어도 · 500 이어도)', () => {
    for (const status of [200, 500]) {
      const r = asErr(parseKto(status, XML_LIMIT));
      expect(r.kind).toBe('quota');
      expect(r.code).toBe('22');
      expect(r.message).toBe('LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR');
      expect(r.status).toBe(status);
    }
  });

  it('② 403 + 키 미등록 XML → upstream · code 30 · returnAuthMsg 그대로', () => {
    const r = asErr(parseKto(403, XML_KEY));
    expect(r.kind).toBe('upstream');
    expect(r.code).toBe('30');
    expect(r.message).toBe('SERVICE_KEY_IS_NOT_REGISTERED_ERROR');
  });

  it('③ 401 + 평면 JSON → upstream · code = HTTP 상태 · message HTTP 401', () => {
    const r = asErr(parseKto(401, '{"resultCode":"20"}'));
    expect(r.kind).toBe('upstream');
    expect(r.code).toBe('401');
    expect(r.message).toBe('HTTP 401');
  });

  it('⑧ 200 + HTML → upstream · 200 + 쓰레기 → upstream non-JSON body', () => {
    const html = asErr(parseKto(200, '<!doctype html><html><body>maintenance</body></html>'));
    expect(html.kind).toBe('upstream');
    expect(html.code).toBe('200');
    const garbage = asErr(parseKto(200, 'garbage'));
    expect(garbage.kind).toBe('upstream');
    expect(garbage.message).toBe('non-JSON body');
  });
});

describe('parseKto (b) HTTP 200 + response 래퍼 없는 평면 JSON', () => {
  it('④ resultCode 11 / 10 → param_error · code · resultMsg 그대로', () => {
    const body11 = '{"responseTime":"2026-09-14T00:00:00","resultCode":"11","resultMsg":"NO_MANDATORY_REQUEST_PARAMETERS_ERROR1(MobileOS)"}';
    const r = asErr(parseKto(200, body11));
    expect(r.kind).toBe('param_error');
    expect(r.code).toBe('11');
    expect(r.message).toBe('NO_MANDATORY_REQUEST_PARAMETERS_ERROR1(MobileOS)');
    const r10 = asErr(parseKto(200, '{"resultCode":"10","resultMsg":"INVALID_REQUEST_PARAMETER_ERROR"}'));
    expect(r10.kind).toBe('param_error');
    expect(r10.code).toBe('10');
  });
});

describe('parseKto (c) resultCode ≠ 0000', () => {
  it('⑤ 03 NODATA_ERROR → api_error · code 03', () => {
    const r = asErr(parseKto(200, wrap({ resultCode: '03', resultMsg: 'NODATA_ERROR' })));
    expect(r.kind).toBe('api_error');
    expect(r.code).toBe('03');
    expect(r.message).toBe('NODATA_ERROR');
  });
});

describe('parseKto (d) 정상 JSON', () => {
  it('⑥ items "" → ok · list [] · totalCount 0', () => {
    const r = asOk(parseKto(200, wrap(OK_HEADER, { items: '', numOfRows: 1000, pageNo: 1, totalCount: 0 })));
    expect(r.list).toEqual([]);
    expect(r.totalCount).toBe(0);
    expect(r.status).toBe(200);
  });

  it('⑥ items.item 객체 1건 → list 길이 1 · 배열 → 그대로 · totalCount 문자열도 숫자로', () => {
    const one = asOk(parseKto(200, wrap(OK_HEADER, { items: { item: { contentid: '1' } }, totalCount: '1' })));
    expect(one.list).toEqual([{ contentid: '1' }]);
    expect(one.totalCount).toBe(1);
    const many = asOk(parseKto(200, wrap(OK_HEADER, { items: { item: [{ contentid: '1' }, { contentid: '2' }] }, totalCount: '142' })));
    expect(many.list.length).toBe(2);
    expect(many.totalCount).toBe(142);
  });

  it('⑦ overview 본문에 errMsg 글자가 섞여도 ok (2026-09-14 회귀)', () => {
    const body = wrap(OK_HEADER, { items: { item: [{ contentid: '9', overview: '안내: errMsg 와 returnAuthMsg 라는 표지판이 있는 OpenAPI_ServiceResponse 전시관' }] }, totalCount: 1 });
    const r = asOk(parseKto(200, body));
    expect(r.list.length).toBe(1);
  });

  it('remaining · limit 은 파서 단계에서는 null (네트워크 계층이 헤더로 채운다)', () => {
    const r = parseKto(200, wrap(OK_HEADER, { items: '', totalCount: 0 }));
    expect(r.remaining).toBeNull();
    expect(r.limit).toBeNull();
  });
});

describe('splitCode — 행정표준코드 5자리 → lDongRegnCd + lDongSignguCd (회귀 #3)', () => {
  it('12xxx(전남광주통합특별시) · 11xxx · 28xxx(인천 신설 4구) · 47xxx', () => {
    expect(splitCode('12730')).toEqual({ lDongRegnCd: '12', lDongSignguCd: '730' });
    expect(splitCode('11110')).toEqual({ lDongRegnCd: '11', lDongSignguCd: '110' });
    for (const sgg of ['125', '155', '275', '290']) {
      expect(splitCode(`28${sgg}`)).toEqual({ lDongRegnCd: '28', lDongSignguCd: sgg });
    }
    expect(splitCode('47170')).toEqual({ lDongRegnCd: '47', lDongSignguCd: '170' });
  });

  it('세종 36110 특례 — 둘 다 36110 (36/110 은 상류 totalCount 0 · 2026-09-14 실측)', () => {
    expect(splitCode('36110')).toEqual({ lDongRegnCd: '36110', lDongSignguCd: '36110' });
  });
});
