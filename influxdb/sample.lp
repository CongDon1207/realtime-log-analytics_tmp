http_stats,env=dev,hostname=web1,method=GET,status_class=2xx count=120i,rps=12.0,avg_rt=0.015,max_rt=0.090,err_rate=0.00
http_stats,env=dev,hostname=web1,method=GET,status_class=5xx count=5i,rps=0.5,avg_rt=0.120,max_rt=0.580,err_rate=1.00
top_urls,env=dev,hostname=web1,status=200,path=/ count=80i
top_urls,env=dev,hostname=web1,status=404,path=/login count=15i
error_events,env=dev,hostname=web1,level=error,upstream=http://10.0.0.5:8080/api count=3i