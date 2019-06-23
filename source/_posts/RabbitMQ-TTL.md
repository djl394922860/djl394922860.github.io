---
title: RabbitMQ Queue 过期机制测试探索
date: 2019-06-22 01:45:08
copyright: ture
categories: 
- 分布式消息队列
tags:
- RabbitMQ
comments: true
---

## 前言

关于RabbitMQ的延时队列 , 官方文档已经给了较为详细的说明文档 , 详情参考链接: <https://www.rabbitmq.com/ttl.html> , 此文主要记录在某些场景下面的RabbitMQ是否表现与我们预期的结果保持一致...

## 摘要

{% note info %} 测试环境: RabbitMQ 3.7.15 Erlang 22.0.3 ( centos 7 + docker ) {% endnote %}

## 正文

> 特别说明: 下面的测试采用 c# + .net core 作为client进行 , 首先设置好如下图所示:死信交换机和与其绑定的死信投递的队列

{% asset_img deal-exchange.png 死信交换机和与其绑定的死信投递的队列 %}

### 问题:关于Queue的x-message-ttl与Message的expiration设置冲突问题思考

#### Message本身没有设置过期时间

> 发布者测试代码如下 , 具体可以参考代码的备注说明

{% codeblock lang:csharp RabbitMQ Publisher https://github.com/djl394922860/Resurrection/blob/master/src/rabbitmq/Test_TTL/Program.cs Program.cs %}
using (var channel = connection.CreateModel())
{
    // 设定一个普通队列,配置参数 x-message-ttl 延迟60s队列 以及 配置死信交换机且该交换机配置了接受过期Msg的队列
    channel.QueueDeclare(queue: "test-ttl",
        durable: true,
        exclusive: false,
        autoDelete: false,
        arguments: new Dictionary<string, object>
        {
            {"x-message-ttl",60000 }, // 注意这里需要是数字格式
            { "x-dead-letter-exchange", "deal-exchange" }, // 这里需要提前指定过期消息投递的交换机以及交换机绑定的queue ( 如果有需要还需指定 route key )
            //{"x-dead-letter-routing-key","key" }
        });

    // 下面发送会使用当前Queue的过期配置
    for (int i = 0; i < 100; i++)
    {
        channel.BasicPublish("", "test-ttl", null, Encoding.UTF8.GetBytes($"我是60s过期_{i}"));
    }
}
{% endcodeblock %}

> 结果如我们所料消息再1分钟之后转移到了死信队列上面 , 默认使用Queue的过期时间

{% asset_img queue-to-deal-exchange.png 过期之后投递到了对应的死信队列上去 %}

#### Message设置Expiration测试

> 这里暂时部分修改代码 , 具体参考链接地址查看全部代码

{% codeblock lang:csharp RabbitMQ Publisher https://github.com/djl394922860/Resurrection/blob/master/src/rabbitmq/Test_TTL/Program.cs Program.cs %}
channel.BasicPublish("", "test-ttl", new BasicProperties()
{
    Expiration = "30000"
}, Encoding.UTF8.GetBytes($"我是30s过期_{i}"));
{% endcodeblock %}

> 结果如上述代码所示 , 在30s( 如果消息本身的过期时间小于Queue的过期时间 , 则使用较小的那个 )之后 , 消息投递到了死信交换机从而最终到了死信队列

{% asset_img 1.png 30s过期之后投递到了对应的死信队列上去 %}

#### Message设置不同的Expiration发布到设置了60s过期得Queue中

{% codeblock lang:csharp RabbitMQ Publisher https://github.com/djl394922860/Resurrection/blob/master/src/rabbitmq/Test_TTL/Program.cs Program.cs %}
// 20s过期
for (int i = 0; i < 20; i++)
{
    channel.BasicPublish("", "test-ttl", new BasicProperties()
    {
        Expiration = "20000"
    }, Encoding.UTF8.GetBytes($"我是20s过期_{i}"));
}

// 40s过期
for (int i = 0; i < 40; i++)
{
    channel.BasicPublish("", "test-ttl", new BasicProperties()
    {
        Expiration = "40000"
    }, Encoding.UTF8.GetBytes($"我是40s过期_{i}"));
}
{% endcodeblock %}

> 结果不言而喻 , rabbitMQ 符合预期的 , 先是前面的20条过期 , 然后是后面的40条消息

{% asset_img 2.png 先是前面的20条过期然后是后面的40条消息投递到了对应的死信队列上去 %}

### 问题: Queue没有设置过期时间测试

> 测试上述相同实验结论如下 , 结果图类似上面 , 所以这里就懒得贴图了哈

* 设置了消息的过期时间则时间一到投递到死信交换机 , 否则消息该咋咋滴

* 如果消息本身过期时间不一致 , 则按照过期时间正常表现 , 参考上述20s和40s消息

## 尾声

此文也是工作中对于某些特殊情况下 , RabbitMQ TTL 的表现行为表示好奇 , 便空闲时候做了一定的测试 , 并记录在案 , 方便自己和其他人查阅 !!
