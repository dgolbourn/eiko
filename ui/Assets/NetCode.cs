using System.Collections;
using System.Collections.Generic;
using UnityEngine;

using System.Diagnostics;
using System.Net.Sockets;
using System.Net;


public class NetCode : MonoBehaviour
{
    public class IncomingData
    {

    }

    public class OutgoingData
    {

    }

    Process netCode;
    UdpClient udpClient;
    IPEndPoint ep;
    public IncomingData data;

    void Start()
    {
        netCode = Process.Start("luajit.exe", "eiko/main.lua client config.yaml");
        udpClient = new UdpClient();
        ep = new IPEndPoint(IPAddress.Parse("127.0.0.1"), 11000);
        udpClient.Connect(ep);
    }

    void Update()
    {
        if(udpClient.Available > 0)
        {
            var receivedData = udpClient.Receive(ref ep);
            string receivedString = System.Text.Encoding.UTF8.GetString(receivedData, 0, receivedData.Length);
            data = JsonUtility.FromJson<IncomingData>(receivedString);
        }
    }

    void OnDestroy()
    {
        udpClient.Close();
        netCode.Close();
    }

    public void Send(OutgoingData data)
    {
        var outgoingJSON = JsonUtility.ToJson(data);
        var  outgoingBytes = System.Text.Encoding.UTF8.GetBytes(outgoingJSON);
        udpClient.Send(outgoingBytes, outgoingBytes.Length);
    }
}
