import os;
import requests;
import from mtllm.llm {Model}
import from httpx  {get}

glob llm = Model(model_name="gpt-4o");

obj WebSearch {
    has api_key: str = os.getenv("SERPER_API_KEY");
    has base_url: str = "https://google.serper.dev/search";

    def search(query: str) {
        headers = {"X-API-KEY": self.api_key, "Content-Type": "application/json"};
        payload = {"q": query};
        resp = requests.post(self.base_url, headers=headers, json=payload);
        if resp.status_code == 200 {
            data = resp.json();
            summary = "";
            results = data.get("organic", []) if isinstance(data, dict) else [];
            for r in results[:3] {
                summary += f"{r.get('title', '')}: {r.get('link', '')}\n";
                if r.get('snippet') {
                    summary += f"{r['snippet']}\n";
                }
            }
            return summary;
        }
        return f"Serper request failed: {resp.status_code}";
    }
}

def search_web(query: str) -> str { return WebSearch().search(query=query); }

"""You are a cheerful travel buddy.
TASK:
1. Find next Saturday (YYYY-MM-DD).
2. Get weather: search_web("weather Saturday {location} {date}").
   - GOOD = no 'rain'/'storm' & precip<30%.
3. If GOOD:
    a) search_web("outdoor events {location} {date}").
    b) Pick 1 event → {name, time, venue, 1 fun fact}.
    c) Add 1 nearby outdoor bonus spot (with why it’s cool).
4. If BAD:
    a) search_web("indoor things to do {location} {date}").
    b) Pick 1 activity → {name, hours, location, approx cost}.
5. Reply as 1 friendly paragraph:
    [Greet + Weather] → [Main rec] → [Bonus/cosy alt + cost] → [Enthusiastic closing]."""
def weekend_plan(location:str)->str by llm(method="ReAct",tools=[search_web]);

with entry {print(weekend_plan("Michigan, USA"));}
