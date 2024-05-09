set -x 

lpips_lambda=0.8

image_size=128 # final rendered resolution
image_size_encoder=256

patch_size=14

batch_size=20 # 24.074 gib on ditb/2. 10M/iter


microbatch=${batch_size}

cfg_dropout_prob=0.1 # SD config

dataset_name="8cls"

num_workers=4


# NUM_GPUS=8
NUM_GPUS=4
shards_lst=shell_scripts/shards_list/diffusion_shards/diff_shards_lst_8cls-hwc.txt
eval_shards_lst=${shards_lst}

DATASET_FLAGS="
 --data_dir "NONE" \
 --shards_lst ${shards_lst} \
 --eval_data_dir "NONE" \
 --eval_shards_lst ${eval_shards_lst}  \
"


lr=1e-4
kl_lambda=0
vit_lr=1e-5 # for improved-diffusion unet
ce_lambda=0.5 # ?
conv_lr=5e-5
alpha_lambda=1
scale_clip_encoding=1

triplane_scaling_divider=0.90

# * above the best lr config

LR_FLAGS="--encoder_lr $vit_lr \
 --vit_decoder_lr $vit_lr \
 --lpips_lambda $lpips_lambda \
 --triplane_decoder_lr $conv_lr \
 --super_resolution_lr $conv_lr \
 --lr $lr \
 --kl_lambda ${kl_lambda} \
 --bg_lamdba 0.01 \
 --alpha_lambda ${alpha_lambda} \
"

TRAIN_FLAGS="--iterations 10001 --anneal_lr False \
 --batch_size $batch_size --save_interval 10000 \
 --microbatch ${microbatch} \
 --image_size_encoder $image_size_encoder \
 --image_size $image_size \
 --dino_version mv-sd-dit \
 --sr_training False \
 --encoder_cls_token False \
 --decoder_cls_token False \
 --cls_token False \
 --weight_decay 0.05 \
 --no_dim_up_mlp True \
 --uvit_skip_encoder True \
 --decoder_load_pretrained True \
 --fg_mse False \
 --vae_p 2 \
 --plucker_embedding True \
 --encoder_in_channels 10 \
 --arch_dit_decoder DiT2-B/2 \
 --sd_E_ch 64 \
 --sd_E_num_res_blocks 1 \
 --lrm_decoder False \
 "


DDPM_MODEL_FLAGS="
--learn_sigma False \
--num_heads 8 \
--num_res_blocks 2 \
--num_channels 320 \
--attention_resolutions "4,2,1" \
--use_spatial_transformer True \
--transformer_depth 1 \
--context_dim 768 \
"
# --pred_type x0 \
# --iw_sample_p drop_all_uniform \
# --loss_type x0 \

# ! diffusion steps and noise schedule not used, since the continuous diffusion is adopted.
DIFFUSION_FLAGS="--diffusion_steps 1000 --noise_schedule linear \
--use_kl False \
--triplane_scaling_divider ${triplane_scaling_divider} \
--trainer_name sgm_legacy \
--mixed_prediction False \
--train_vae False \
--denoise_in_channels 4 \
--denoise_out_channels 4 \
--diffusion_input_size 32 \
--diffusion_ce_anneal True \
--create_controlnet False \
--p_rendering_loss False \
--pred_type x_start \
--predict_v False \
--create_dit True \
--dit_model_arch DiT-B/2 \
--train_vae False \
--use_eos_feature False \
--roll_out True \
"

logdir=/mnt/lustre/yslan/logs/nips24/LSGM/cldm-unet/mv/t23d/sgm-engine/${dataset_name}/gpu${NUM_GPUS}-batch${batch_size}-lr${lr}-ditvb2-globalAttn

SR_TRAIN_FLAGS_v1_2XC="
--decoder_in_chans 32 \
--out_chans 96 \
--ae_classname vit.vit_triplane.RodinSR_256_fusionv6_ConvQuant_liteSR_dinoInit3DAttn_SD_B_3L_C_withrollout_withSD_D_ditDecoder \
--logdir $logdir \
--arch_encoder vits \
--arch_decoder vitb \
--vit_decoder_wd 0.001 \
--encoder_weight_decay 0.001 \
--color_criterion mse \
--triplane_in_chans 32 \
--decoder_output_dim 3 \
--resume_checkpoint /home/yslan/Repo/open-source/ln3diff-lint-code/checkpoints/objaverse/model_rec1680000.pt \
"

# --resume_checkpoint /mnt/lustre/yslan/logs/nips24/LSGM/cldm-unet/mv/t23d/sgm-engine/8cls/gpu8-batch6-lr5e-5-ditl2-globalAttn-ctd/model_joint_denoise_rec_model1780000.pt \


SR_TRAIN_FLAGS=${SR_TRAIN_FLAGS_v1_2XC}


rm -rf "$logdir"/runs
mkdir -p "$logdir"/
cp "$0" "$logdir"/

export OMP_NUM_THREADS=12
export LC_ALL=en_US.UTF-8 # save caption txt bug
export NCCL_ASYNC_ERROR_HANDLING=1
export OPENCV_IO_ENABLE_OPENEXR=1
export NCCL_IB_GID_INDEX=3 # https://github.com/huggingface/accelerate/issues/314#issuecomment-1821973930
# export CUDA_VISIBLE_DEVICES=0,1,2

export CUDA_VISIBLE_DEVICES=0,1,2,3

torchrun --nproc_per_node=$NUM_GPUS \
  --nnodes 1 \
  --rdzv-endpoint=localhost:23371 \
 scripts/vit_triplane_diffusion_train.py \
 --num_workers ${num_workers} \
 --depth_lambda 0 \
 ${TRAIN_FLAGS}  \
 ${SR_TRAIN_FLAGS} \
 ${DATASET_FLAGS} \
 ${DIFFUSION_FLAGS} \
 ${DDPM_MODEL_FLAGS} \
 --overfitting False \
 --load_pretrain_encoder False \
 --iterations 5000001 \
 --save_interval 10000 \
 --eval_interval 5000 \
 --decomposed True \
 --logdir $logdir \
 --cfg objverse_tuneray_aug_resolution_64_64_auto \
 --patch_size ${patch_size} \
 --eval_batch_size 1 \
 ${LR_FLAGS} \
 --ce_lambda ${ce_lambda} \
 --negative_entropy_lambda ${ce_lambda} \
 --triplane_fg_bg False \
 --grad_clip True \
 --interval 5 \
 --normalize_clip_encoding True \
 --scale_clip_encoding ${scale_clip_encoding} \
 --mixing_logit_init 10000 \
 --objv_dataset True \
 --cfg_dropout_prob ${cfg_dropout_prob} \
 --cond_key caption \
 --use_lmdb_compressed False \
 --use_lmdb False \
 --use_amp False \
 --allow_tf32 False \
 --load_wds_diff True \
 --load_wds_latent False \
 --compile False \
 --split_chunk_input True \
 --append_depth True \
 --mv_input True \
 --duplicate_sample False \
 --enable_mixing_normal False \
 --use_wds True \
 --clip_grad_throld 1.0 \
 --mv_latent_dir /home/yslan/dataset/nips24/latents/168w-8cls/latent_dir/
 