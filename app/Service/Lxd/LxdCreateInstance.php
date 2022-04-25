<?php
/**
 * Nuber.io
 * Copyright 2020 - 2021 Jamiel Sharief.
 *
 * SPDX-License-Identifier: AGPL-3.0
 *
 * @copyright   Copyright (c) Jamiel Sharief
 * @link        https://www.nuber.io
 * @license     https://opensource.org/licenses/AGPL-3.0 AGPL-3.0 License
 */
declare(strict_types = 1);
namespace App\Service\Lxd;

use App\Lxd\LxdClient;
use Origin\Service\Result;
use App\Service\ApplicationService;

/**
 * Creates the instance using a local image and assigns a static IP address. The instance
 * will have two devices, eth0 & root
 *
 * @method Result dispatch(string $name, string $fingerprint, string $memory, string $disk, string $cpu, string $eth0)
 */
class LxdCreateInstance extends ApplicationService
{
    use LxdTrait;
    
    private LxdClient $client;
    
    protected function initialize(LxdClient $client): void
    {
        $this->client = $client;
    }
    /**
     * Creates a new Linux Container Instance
     *
     * @param string $name
     * @param string $fingerprint
     * @param string $memory
     * @param string $disk
     * @param string $cpu
     * @param string $eth0
     * @return \Origin\Service\Result|null
     */
    protected function execute(string $name, string $fingerprint, string $memory, string $disk, string $cpu, string $eth0, string $type = 'container'): ?Result
    {
        $config = [
            'profiles' => [],
            'config' => [
                'limits.memory' => $memory,
                'limits.cpu' => (string) $cpu,
            ],
            'devices' => [
                'root' => [
                    'path' => '/',
                    'pool' => 'default',
                    'type' => 'disk'
                ]
            ],
            'type' => $type
        ];

        if ($type === 'virtual-machine') {
            $config['security.secureboot'] = 'false';
        }
       
        $uuid = $this->client->instance->create($fingerprint, $name, $config);

        $response = $this->client->operation->wait($uuid);

        if (! empty($response['err'])) {
            return new Result([
                'error' => [
                    'message' => $response['err'],
                    'code' => $response['status_code'],
                ]
            ]);
        }

        $result = (new LxdChangeNetworkSettings($this->client))->dispatch($name, $eth0);

        if (! $result->success()) {
            return $result;
        }
     
        $this->client->device->set($name, 'root', 'size', $disk);

        return (new LxdStartInstance($this->client))->dispatch($name, true);
    }
}
